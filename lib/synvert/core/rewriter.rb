# frozen_string_literal: true

require 'parallel'
require 'fileutils'

module Synvert::Core
  # Rewriter is the top level namespace in a snippet.
  #
  # One Rewriter checks if the depndency version matches, and it can contain one or many {Synvert::Core::Rewriter::Instance},
  # which define the behavior what files and what codes to detect and rewrite to what code.
  class Rewriter
    DEFAULT_OPTIONS = { run_instance: true, write_to_file: true, parser: 'parser' }.freeze

    autoload :ReplaceErbStmtWithExprAction, 'synvert/core/rewriter/action/replace_erb_stmt_with_expr_action'

    autoload :Warning, 'synvert/core/rewriter/warning'

    autoload :Instance, 'synvert/core/rewriter/instance'

    autoload :Scope, 'synvert/core/rewriter/scope'
    autoload :WithinScope, 'synvert/core/rewriter/scope/within_scope'
    autoload :GotoScope, 'synvert/core/rewriter/scope/goto_scope'

    autoload :Condition, 'synvert/core/rewriter/condition'
    autoload :IfExistCondition, 'synvert/core/rewriter/condition/if_exist_condition'
    autoload :UnlessExistCondition, 'synvert/core/rewriter/condition/unless_exist_condition'
    autoload :IfOnlyExistCondition, 'synvert/core/rewriter/condition/if_only_exist_condition'

    autoload :Helper, 'synvert/core/rewriter/helper'

    autoload :RubyVersion, 'synvert/core/rewriter/ruby_version'
    autoload :GemSpec, 'synvert/core/rewriter/gem_spec'

    class << self
      # Register a rewriter with its group and name.
      #
      # @param group [String] the rewriter group.
      # @param name [String] the unique rewriter name.
      # @param rewriter [Synvert::Core::Rewriter] the rewriter to register.
      def register(group, name, rewriter)
        group = group.to_s
        name = name.to_s
        rewriters[group] ||= {}
        rewriters[group][name] = rewriter
      end

      # Fetch a rewriter by group and name.
      #
      # @param group [String] rewrtier group.
      # @param name [String] rewrtier name.
      # @return [Synvert::Core::Rewriter] the matching rewriter.
      def fetch(group, name)
        group = group.to_s
        name = name.to_s
        rewriters.dig(group, name)
      end

      # Get all available rewriters
      #
      # @return [Hash<String, Hash<String, Synvert::Core::Rewriter>>]
      def availables
        rewriters
      end

      # Clear all registered rewriters.
      def clear
        rewriters.clear
      end

      private

      def rewriters
        @rewriters ||= {}
      end
    end

    # @!attribute [r] group
    #   @return [String] the group of rewriter
    # @!attribute [r] name
    #   @return [String] the unique name of rewriter
    # @!attribute [r] sub_snippets
    #   @return [Array<Synvert::Core::Rewriter>] all rewriters this rewiter calls.
    # @!attribute [r] helper
    #   @return [Array] helper methods.
    # @!attribute [r] warnings
    #   @return [Array<Synvert::Core::Rewriter::Warning>] warning messages.
    # @!attribute [r] affected_files
    #   @return [Set] affected fileds
    # @!attribute [r] ruby_version
    #   @return [Rewriter::RubyVersion] the ruby version
    # @!attribute [r] gem_spec
    #   @return [Rewriter::GemSpec] the gem spec
    # @!attribute [r] test_results
    #   @return [Hash<String, Object>] the test results
    # @!attribute [rw] options
    #   @return [Hash] the rewriter options
    attr_reader :group,
                :name,
                :sub_snippets,
                :helpers,
                :warnings,
                :affected_files,
                :ruby_version,
                :gem_spec,
                :test_results
    attr_accessor :options

    # Initialize a Rewriter.
    # When a rewriter is initialized, it is already registered.
    #
    # @param group [String] group of the rewriter.
    # @param name [String] name of the rewriter.
    # @yield defines the behaviors of the rewriter, block code won't be called when initialization.
    def initialize(group, name, &block)
      @group = group
      @name = name
      @block = block
      @helpers = []
      @sub_snippets = []
      @options = DEFAULT_OPTIONS.dup
      reset
      self.class.register(@group, @name, self)
    end

    # Process the rewriter.
    # It will call the block.
    def process
      @affected_files = Set.new
      instance_eval(&@block)
    end

    # Process rewriter with sandbox mode.
    # It will call the block but doesn't change any file.
    def process_with_sandbox
      @options[:run_instance] = false
      process
    end

    def test
      @options[:write_to_file] = false
      @affected_files = Set.new
      instance_eval(&@block)

      if Configuration.test_result == 'new_source'
        @test_results.values.flatten
      else
        @test_results.map do |filename, test_results|
          new_actions = test_results.map(&:actions).flatten.sort_by(&:end)
          last_start = -1
          conflicted =
            new_actions.any? do |action|
              if last_start > action.end
                true
              else
                last_start = action.start
                false
              end
            end
          result = NodeMutation::Result.new(affected: true, conflicted: conflicted)
          result.actions = new_actions
          result.file_path = filename
          result
        end
      end
    end

    # Add a warning.
    #
    # @param warning [Synvert::Core::Rewriter::Warning]
    def add_warning(warning)
      @warnings << warning
    end

    # Add an affected file.
    #
    # @param file_path [String]
    def add_affected_file(file_path)
      @affected_files.add(file_path)
    end

    def parser
      @options[:parser]
    end

    # Reset @warnings, @affected_files, and @test_results.
    def reset
      @warnings = []
      @affected_files = Set.new
      @test_results = Hash.new { |h, k| h[k] = [] }
    end

    #######
    # DSL #
    #######

    # Configure the rewriter
    # @example
    #   configure({ parser: Synvert::PARSER_PARSER })
    #   configure({ strategy: 'allow_insert_at_same_position' })
    # @param options [Hash]
    # @option parser [String] Synvert::PARSER_PARSER, Synvert::SYNTAX_TREE_PARSER, or Synvert::PRISM_PARSER
    # @option strategy [String] 'allow_insert_at_same_position'
    def configure(options)
      @options = @options.merge(options)
      if options[:parser] && ![
        Synvert::PARSER_PARSER,
        Synvert::SYNTAX_TREE_PARSER,
        Synvert::PRISM_PARSER
      ].include?(options[:parser])

        raise Errors::ParserNotSupported.new("Parser #{options[:parser]} not supported")
      end
    end

    # It sets description of the rewrite or get description.
    # @example
    #   Synvert::Rewriter.new 'rspec', 'use_new_syntax' do
    #     description 'It converts rspec code to new syntax, it calls all rspec sub snippets.'
    #   end
    # @param description [String] rewriter description.
    # @return rewriter description.
    def description(description = nil)
      if description
        @description = description
      else
        @description
      end
    end

    # It checks if ruby version is greater than or equal to the specified ruby version.
    # @example
    #   Synvert::Rewriter.new 'ruby', 'new_safe_navigation_operator' do
    #     if_ruby '2.3.0'
    #   end
    # @param version [String] specified ruby version.
    def if_ruby(version)
      @ruby_version = Rewriter::RubyVersion.new(version)
    end

    # It compares version of the specified gem.
    # @example
    #   Synvert::Rewriter.new 'rails', 'upgrade_5_2_to_6_0' do
    #     if_gem 'rails', '>= 6.0'
    #   end
    # @param name [String] gem name.
    # @param version [String] equal, less than or greater than specified version, e.g. '>= 2.0.0',
    def if_gem(name, version)
      @gem_spec = Rewriter::GemSpec.new(name, version)
    end

    # It finds specified files, and for each file, it will delegate to {Synvert::Core::Rewriter::Instance} to rewrite code.
    # It creates a {Synvert::Core::Rewriter::Instance} to rewrite code.
    # @example
    #   Synvert::Rewriter.new 'rspec', 'be_close_to_be_within' do
    #     within_files '**/*.rb' do
    #     end
    #   end
    # @param file_patterns [String|Array<String>] string pattern or list of string pattern to find files, e.g. ['spec/**/*_spec.rb']
    # @param block [Block] the block to rewrite code in the matching files.
    def within_files(file_patterns, &block)
      return unless @options[:run_instance]

      return if @ruby_version && !@ruby_version.match?
      return if @gem_spec && !@gem_spec.match?

      if @options[:write_to_file]
        handle_one_file(Array(file_patterns)) do |file_path|
          instance = Instance.new(self, file_path, &block)
          instance.process
        end
      else
        results =
          handle_one_file(Array(file_patterns)) do |file_path|
            instance = Instance.new(self, file_path, &block)
            instance.test
          end
        merge_test_results(results)
      end
    end

    # It finds a specifiled file.
    alias within_file within_files

    # It adds a new file.
    # @example
    #   Synvert::Rewriter.new 'rails', 'add_application_record' do
    #     add_file 'app/models/application_record.rb', <<~EOS
    #       class ApplicationRecord < ActiveRecord::Base
    #         self.abstract_class = true
    #       end
    #     EOS
    #   end
    # @param filename [String] file name of newly created file.
    # @param content [String] file body of newly created file.
    def add_file(filename, content)
      return unless @options[:run_instance]

      unless @options[:write_to_file]
        result = NodeMutation::Result.new(affected: true, conflicted: false)
        if Configuration.test_result == 'new_source'
          result.new_source = content
        else
          result.actions = [NodeMutation::Struct::Action.new(:add_file, 0, 0, content)]
        end
        result.file_path = filename
        merge_test_result(result)
        return
      end

      filepath = File.join(Configuration.root_path, filename)
      if File.exist?(filepath)
        puts "File #{filepath} already exists."
        return
      end

      FileUtils.mkdir_p File.dirname(filepath)
      File.write(filepath, content)
    end

    # It removes a file.
    # @example
    #   Synvert::Rewriter.new 'rails', 'upgrade_4_0_to_4_1' do
    #     remove_file 'config/initializers/secret_token.rb'
    #   end
    # @param filename [String] file name.
    def remove_file(filename)
      return unless @options[:run_instance]

      unless @options[:write_to_file]
        result = NodeMutation::Result.new(affected: true, conflicted: false)
        if Configuration.test_result == 'new_source'
          result.new_source = nil
        else
          result.actions = [NodeMutation::Struct::Action.new(:remove_file, 0, -1)]
        end
        result.file_path = filename
        merge_test_result(result)
        return
      end

      file_path = File.join(Configuration.root_path, filename)
      File.delete(file_path) if File.exist?(file_path)
    end

    # It calls anther rewriter.
    # @example
    #   Synvert::Rewriter.new 'minitest', 'better_syntax' do
    #     add_snippet 'minitest', 'assert_empty'
    #     add_snippet 'minitest', 'assert_equal_arguments_order'
    #     add_snippet 'minitest/assert_instance_of'
    #     add_snippet 'minitest/assert_kind_of'
    #     add_snippet '/Users/flyerhzm/.synvert-ruby/lib/minitest/assert_match.rb'
    #     add_snippet '/Users/flyerhzm/.synvert-ruby/lib/minitest/assert_nil.rb'
    #     add_snippet 'https://github.com/xinminlabs/synvert-snippets-ruby/blob/main/lib/minitest/assert_silent.rb'
    #     add_snippet 'https://github.com/xinminlabs/synvert-snippets-ruby/blob/main/lib/minitest/assert_truthy.rb'
    #   end
    # @param group [String] group of another rewriter, if there's no name parameter, the group can be http url, file path or snippet name.
    # @param name [String] name of another rewriter.
    def add_snippet(group, name = nil)
      rewriter =
        if name
          Rewriter.fetch(group, name) || Utils.eval_snippet([group, name].join('/'))
        else
          Utils.eval_snippet(group)
        end
      return unless rewriter && rewriter.is_a?(Rewriter)

      rewriter.options = @options
      preserve_current_parser do
        if !rewriter.options[:write_to_file]
          results = rewriter.test
          merge_test_results(results)
        elsif rewriter.options[:run_instance]
          rewriter.process
        else
          rewriter.process_with_sandbox
        end
      end
      @sub_snippets << rewriter
    end

    # It calls a shared rewriter.
    # @example
    #   Synvert::Rewriter.new 'rails', 'upgrade_6_0_to_6_1' do
    #     call_helper 'rails/set_load_defaults', rails_version: '6.1'
    #     add_snippet '/Users/flyerhzm/.synvert-ruby/lib/rails/set_load_defaults.rb', rails_version: '6.1'
    #     add_snippet 'https://github.com/xinminlabs/synvert-snippets-ruby/blob/main/lib/rails/set_load_defaults.rb', rails_version: '6.1'
    #   end
    # @param name [String] name of helper.
    # @param options [Hash] options to pass to helper.
    def call_helper(name, options = {})
      helper = Synvert::Core::Helper.fetch(name) || Utils.eval_snippet(name)
      return unless helper && helper.is_a?(Synvert::Core::Helper)

      preserve_current_parser do
        instance_exec(options, &helper.block)
      end
    end

    # It defines helper method for {Synvert::Core::Rewriter::Instance}.
    # @example
    #   Synvert::Rewriter.new 'rails', 'convert_active_record_dirty_5_0_to_5_1' do
    #     helper_method :find_callbacks_and_convert do |callback_names, callback_changes|
    #       # do anything, method find_callbacks_and_convert can be reused later.
    #     end
    #     within_files Synvert::RAILS_MODEL_FILES + Synvert::RAILS_OBSERVER_FILES do
    #       find_callbacks_and_convert(before_callback_names, before_callback_changes)
    #       find_callbacks_and_convert(after_callback_names, after_callback_changes)
    #     end
    #   end
    # @param name [String] helper method name.
    # @yield helper method block.
    def helper_method(name, &block)
      @helpers << { name: name, block: block }
    end

    # Executes a block of code with temporary configurations.
    #
    # @param configurations [Hash] The temporary configurations to apply.
    # @yield The block of code to execute.
    def with_configurations(configurations, &block)
      Configuration.with_temporary_configurations(configurations, &block)
    end

    # Saves data with a given key and value.
    #
    # @param key [Symbol] the key to identify the data
    # @param value [Object] the value to be saved
    def save_data(key, value)
      Synvert::Core.instance_variable_set("@#{key}", value)
    end

    # Loads data with the given key.
    #
    # @param key [Symbol] the key of the data to be loaded
    # @return [Object] the data loaded
    def load_data(key)
      Synvert::Core.instance_variable_get("@#{key}")
    end

    private

    # Handle one file.
    # @param file_patterns [String] file patterns to find files.
    # @yield [file_path] block to handle file.
    # @yieldparam file_path [String] file path.
    def handle_one_file(file_patterns)
      if Configuration.number_of_workers > 1
        Parallel.map(Utils.glob(file_patterns), in_processes: Configuration.number_of_workers) do |file_path|
          yield(file_path)
        end
      else
        Utils.glob(file_patterns).map do |file_path|
          yield(file_path)
        end
      end
    end

    def merge_test_results(results)
      results.compact.select(&:affected?).each do |result|
        merge_test_result(result)
      end
    end

    def merge_test_result(result)
      @test_results[result.file_path] << result
    end

    def preserve_current_parser
      current_parser = @options[:parser]
      yield
    ensure
      @options[:parser] = current_parser
    end
  end
end
