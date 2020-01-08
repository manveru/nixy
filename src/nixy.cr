require "easy-cli"
require "file_utils"
require "json"

module Nixy
  VERSION = "0.1.0"

  PACKAGES_JSON = File.join ENV["XDG_CONFIG_HOME"], "/nixy/packages.json"
  PACKAGES_NIX  = File.join ENV["XDG_CONFIG_HOME"], "/nixy/packages.nix"
  SOURCES_JSON  = File.join ENV["XDG_CONFIG_HOME"], "/nixy/sources.json"

  PACKAGES_NIX_TEMPLATE = {{ read_file("#{__DIR__}/packages.nix") }}

  module RegistryHelper
    def profile_result(attr : String) : String | Nil
      args = [PACKAGES_NIX, "--no-out-link",
              "--argstr", "name", profile_name,
              "--argstr", "packagesJSON", PACKAGES_JSON,
              "-A", attr,
      ]

      output = IO::Memory.new
      status = Process.run("nix-build", args, error: STDERR, output: output)
      output.to_s.strip if status.success?
    end

    def profile_name
      "nixy-env"
    end

    def registry!(&block : Registry -> _)
      old = File.read(PACKAGES_JSON)
      reg = Registry.from_json(old).tap(&block)

      File.write(PACKAGES_JSON, reg.to_pretty_json)

      profile_path = profile_result("profile")
      if profile_path
        puts "installing profile #{profile_path} ..."
        args = ["-i", profile_path]
        result = Process.run("nix-env", args, error: STDOUT, output: STDOUT)

        File.write(PACKAGES_JSON, old) unless result.success?
      else
        File.write(PACKAGES_JSON, old)
      end
    end

    def listing
      output = IO::Memory.new
      Process.run("nix", ["eval", "--json", "((import #{PACKAGES_NIX} {}).listing)"], output: output, error: output)
      Array(ListingEntry).from_json(output.to_s)
    end

    class ListingEntry
      JSON.mapping(name: String, description: String?)
    end

    def registry(&block : Registry -> _)
      File.open(PACKAGES_JSON) do |io|
        Registry.from_json(io).tap(&block)
      end
    end
  end

  class UI < Easy_CLI::CLI
    def initialize
      name "nixy"
    end

    class Version < Easy_CLI::Command
      def initialize
        name "version"
        desc "Show version of nixy"
      end

      def call(data)
        puts "nixy #{Nixy::VERSION}"
      end
    end

    class Add < Easy_CLI::Command
      include Nixy::RegistryHelper

      def initialize
        name "add"
        argument "package"
        desc "Add the given package to your environment"
      end

      def call(data)
        registry! do |r|
          r.add data["package"].as(String)
        end
      end
    end

    class Remove < Easy_CLI::Command
      include Nixy::RegistryHelper

      def initialize
        name "remove"
        argument "package"
        desc "Remove the given package from your environment"
      end

      def call(data)
        registry! do |r|
          r.remove data["package"].as(String)
        end
      end
    end

    class List < Easy_CLI::Command
      include Nixy::RegistryHelper

      def initialize
        name "list"
        desc "List packages in your environment"
      end

      def call(data)
        listing.each do |l|
          puts "%30s : %s" % [l.name, l.description || "-"]
        end
      end
    end

    class Init < Easy_CLI::Command
      include Nixy::RegistryHelper

      def initialize
        name "init"
        desc "Install files needed for using Nixy"
      end

      def call(data)
        unless File.file?(PACKAGES_NIX)
          FileUtils.mkdir_p File.dirname(PACKAGES_NIX)
          File.write(PACKAGES_NIX, PACKAGES_NIX_TEMPLATE)
        end

        unless File.file?(PACKAGES_JSON)
          FileUtils.mkdir_p File.dirname(PACKAGES_JSON)
          File.write(PACKAGES_JSON, Registry.new([] of String).to_pretty_json)
        end

        unless File.file?(SOURCES_JSON)
          FileUtils.mkdir_p File.dirname(SOURCES_JSON)
          File.write(
            SOURCES_JSON,
            {
              "soures" => {
                "nixpkgs" => {
                  "branch"       => "nixpkgs-unstable",
                  "owner"        => "NixOS",
                  "repo"         => "nixpkgs-channels",
                  "rev"          => "cc6cf0a96a627e678ffc996a8f9d1416200d6c81",
                  "sha256"       => "1srjikizp8ip4h42x7kr4qf00lxcp1l8zp6h0r1ddfdyw8gv9001",
                  "type"         => "github",
                  "url_template" => "https://github.com/<owner>/<repo>/archive/<rev>.tar.gz",
                },
              },
            }.to_pretty_json
          )
        end
      end
    end

    class Sources < Easy_CLI::Command
      include Nixy::RegistryHelper

      def initialize
        name "sources"
        desc "Manipulate the sources for your packages"

        register Update.new
        register List.new
        register Add.new
      end

      def call(data)
        raise "Not implemented"
      end

      class List < Easy_CLI::Command
        def initialize
          name "list"
          desc "List sources"
        end

        def call(data)
          sources = Nixy::Sources.from_json(File.read(SOURCES_JSON))
          sources.sources.each do |name, value|
            pp! name
            pp! value
            pp! value.url
          end
        end
      end

      class Update < Easy_CLI::Command
        def initialize
          name "update"
          desc "Update your sources"
        end

        def call(data)
          sources = Nixy::Sources.from_json(File.read(SOURCES_JSON))
          sources.sources.each do |name, value|
            value.update
          end

          File.write(SOURCES_JSON, sources.to_pretty_json)
        end
      end

      class Add < Easy_CLI::Command
        def initialize
          name "add"
          desc "Add entry to your sources"
          argument "url"
        end

        def call(data)
          case url = data["url"]
          when %r(([^/]+)/([^/]+))
            sources = Nixy::Sources.from_json(File.read(SOURCES_JSON))
            sources.sources[$2] = Nixy::Sources::Source.new(
              owner: $1,
              repo: $2,
              type: "github",
              branch: "master",
              url_template: "https://github.com/<owner>/<repo>/archive/<rev>.tar.gz"
            )
            File.write(SOURCES_JSON, sources.to_pretty_json)
          else
            raise "This syntax is not supported yet, try 'owner/repo'"
            pp! url
          end
        end
      end
    end
  end

  class Registry
    JSON.mapping(packages: Array(String))

    def initialize(@packages)
    end

    def add(package)
      self.packages = (packages | [package]).sort
    end

    def remove(package)
      self.packages = (packages - [package]).sort
    end

    def list
      packages.each do |package|
        puts package
      end
    end
  end

  class Sources
    JSON.mapping(sources: Hash(String, Source))

    class Source
      JSON.mapping(
        type: String,
        url_template: String,
        branch: String,
        owner: String,
        repo: String,
        rev: String,
        sha256: String,
      )

      def initialize(@owner, @repo, @type, @branch, @url_template)
        @rev = update_rev
        @sha256 = update_sha256
      end

      def url
        url_template.gsub(/<([^>]+)>/) {
          self[$1]
        }
      end

      def update
        update_rev
        update_sha256
      end

      def update_rev
        output = IO::Memory.new

        case type
        when "github"
          Process.run("git", ["ls-remote", "https://github.com/#{owner}/#{repo}", branch], output: output)
        end

        hash = output.to_s.split("\t").first.strip
        puts "Found rev: #{hash}"
        @rev = hash
      end

      def update_sha256
        output = IO::Memory.new

        case type
        when "github"
          Process.run("nix-prefetch-url", ["--unpack", url], output: output)
        end

        hash = output.to_s.strip
        puts "Found sha256: #{hash}"
        @sha256 = hash
      end

      def [](key)
        case key
        when "rev"
          rev
        when "branch"
          branch
        when "owner"
          owner
        when "repo"
          repo
        else
          raise "Invalid key used in url_template: '#{key}'"
        end
      end
    end
  end

  def self.run(args = ARGV)
    cli = UI.new
    cli.register UI::Version.new
    cli.register UI::Add.new
    cli.register UI::Remove.new
    cli.register UI::List.new
    cli.register UI::Init.new
    cli.register UI::Sources.new
    cli.run(args)
  end
end

Nixy.run
