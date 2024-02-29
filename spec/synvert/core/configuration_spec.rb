require 'spec_helper'

module Synvert::Core
  RSpec.describe Configuration do
    after do
      Configuration.number_of_workers = nil
      Configuration.strict = nil
    end

    describe '.with_temporary_configurations' do
      it 'temporarily sets instance variables and restores them after block execution' do
        Configuration.number_of_workers = 4
        Configuration.strict = true

        Configuration.with_temporary_configurations(number_of_workers: 1, strict: false) do
          expect(Configuration.number_of_workers).to eq(1)
          expect(Configuration.strict).to eq(false)
        end

        expect(Configuration.number_of_workers).to eq(4)
        expect(Configuration.strict).to eq(true)
      end
    end
  end
end
