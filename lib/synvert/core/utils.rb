# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'open-uri'
require 'open3'

module Synvert::Core
  class Utils
    class << self
      def eval_snippet(snippet_name)
        eval(load_snippet(snippet_name), binding, "(eval #{snippet_name})")
      end

      def load_snippet(snippet_name)
        if is_valid_url?(snippet_name)
          uri = URI.parse(format_url(snippet_name))
          return uri.open.read if remote_snippet_exists?(uri)

          raise Errors::SnippetNotFound.new("#{snippet_name} not found")
        elsif is_valid_file?(snippet_name)
          return File.read(snippet_name)
        else
          snippet_path = snippet_expand_path(snippet_name)
          return File.read(snippet_path) if File.exist?(snippet_path)

          snippet_uri = URI.parse(format_url(remote_snippet_url(snippet_name)))
          return snippet_uri.open.read if remote_snippet_exists?(snippet_uri)

          raise Errors::SnippetNotFound.new("#{snippet_name} not found")
        end
      end

      # Glob file paths.
      # @param file_patterns [Array<String>] file patterns
      # @return [Array<String>] file paths
      def glob(file_patterns)
        Dir.chdir(Configuration.root_path) do
          all_files = file_patterns.flat_map { |pattern| Dir.glob(pattern) }
          ignored_files = []

          if Configuration.respect_gitignore
            Open3.popen3('git check-ignore --stdin') do |stdin, stdout, _stderr, _wait_thr|
              stdin.puts(all_files.join("\n"))
              stdin.close

              ignored_files = stdout.read.split("\n")
            end
          end

          filtered_files = filter_only_paths(all_files - ignored_files)

          filtered_files -= get_explicitly_skipped_files
        end
      end

      private

      def is_valid_url?(url)
        /^http/.match?(url)
      end

      def is_valid_file?(path)
        File.exist?(path)
      end

      def remote_snippet_exists?(uri)
        req = Net::HTTP.new(uri.host, uri.port)
        req.use_ssl = uri.scheme == 'https'
        res = req.request_head(uri.path)
        res.code == "200"
      end

      def snippet_expand_path(snippet_name)
        File.join(default_snippets_home(), 'lib', "#{snippet_name}.rb")
      end

      def default_snippets_home
        ENV['SYNVERT_SNIPPETS_HOME'] || File.join(ENV['HOME'], '.synvert-ruby')
      end

      def remote_snippet_url(snippet_name)
        "https://github.com/xinminlabs/synvert-snippets-ruby/blob/main/lib/#{snippet_name}.rb"
      end

      def format_url(url)
        convert_to_github_raw_url(url)
      end

      def convert_to_github_raw_url(url)
        return url unless url.include?('//github.com/')

        url.sub('//github.com/', '//raw.githubusercontent.com/').sub('/blob/', '/')
      end

      # Filter only paths with `Configuration.only_paths`.
      # @return [Array<String>] filtered file paths
      def filter_only_paths(all_files)
        return all_files if Configuration.only_paths.empty?

        Configuration.only_paths.flat_map do |only_path|
          all_files.filter { |file_path| file_path.starts_with?(only_path) }
        end
      end

      # Get skipped files.
      # @return [Array<String>] skipped files
      def get_explicitly_skipped_files
        Configuration.skip_paths.flat_map do |skip_path|
          if File.directory?(skip_path)
            Dir.glob(File.join(skip_path, "**/*"))
          elsif File.file?(skip_path)
            [skip_path]
          elsif skip_path.end_with?("**") || skip_path.end_with?("**/")
            Dir.glob(File.join(skip_path, "*"))
          else
            Dir.glob(skip_path)
          end
        end
      end
    end
  end
end
