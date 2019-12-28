require "easy-cli"
require "file_utils"
require "json"

module Nixy
  VERSION = "0.1.0"

  PACKAGES_JSON = File.join ENV["XDG_CONFIG_HOME"], "/nixy/packages.json"
  PACKAGES_NIX = File.join ENV["XDG_CONFIG_HOME"], "/nixy/packages.nix"

  PACKAGES_NIX_TEMPLATE = {{ read_file("#{__DIR__}/packages.nix") }}

  module RegistryHelper
    def profile_result(attr : String) : String | Nil
      FileUtils.mkdir_p File.dirname(PACKAGES_NIX)
      File.write(PACKAGES_NIX, PACKAGES_NIX_TEMPLATE)

      args = [PACKAGES_NIX, "--no-out-link",
              "--argstr", "name", profile_name,
              "--argstr", "packagesJSON", PACKAGES_JSON,
              "-A", attr
             ]

      output = IO::Memory.new
      status = Process.run("nix-build", args, error: STDERR, output: output)
      output.to_s.strip if status.success?
    end

    def profile_name
      "nixy-env"
    end

    private def ensure_registry
      FileUtils.mkdir_p File.dirname(PACKAGES_JSON)
      return if File.file?(PACKAGES_JSON)
      File.write(PACKAGES_JSON, Registry.new([] of String).to_pretty_json)
    end

    def registry!(&block : Registry -> _)
      ensure_registry

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
      ensure_registry

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
  end

  class Registry
    JSON.mapping(packages: Array(String))

    def initialize(@packages)
    end

    def add(package)
      self.packages = (packages | [package]).sort
    end

    def remove(package)
      self.packages = (packages  - [package]).sort
    end

    def list
      packages.each do |package|
        puts package
      end
    end
  end

  def self.run(args = ARGV)
    cli = UI.new
    cli.register UI::Version.new
    cli.register UI::Add.new
    cli.register UI::Remove.new
    cli.register UI::List.new
    cli.run(args)
  end
end

Nixy.run
