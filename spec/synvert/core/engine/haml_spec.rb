# frozen_string_literal: true

require 'spec_helper'

module Synvert::Core
  describe Engine::Haml do
    it 'encodes / decodes' do
      source = <<~EOF
        %p
          Date/Time:
          - now = DateTime.now
          %strong= now
          - if now > DateTime.parse("December 31, 2006")
            = "Happy new " + "year!"
          - else
            = "Hello!"
          - if current_admin?
            %strong= "Admin"
          - elsif current_user?
            %span= "User"
        #error= error_message
        .form-actions
          = form_for @user do |f|
        Test
      EOF
      encoded_source = Engine::Haml.encode(source)
      expect(encoded_source).to be_include 'now = DateTime.now'
      expect(encoded_source).to be_include 'now'
      expect(encoded_source).to be_include 'if now > DateTime.parse("December 31, 2006")'
      expect(encoded_source).to be_include '"Happy new " + "year!"'
      expect(encoded_source).to be_include '"Hello!"'
      expect(encoded_source).to be_include 'if current_admin?'
      expect(encoded_source).to be_include '"Admin"'
      expect(encoded_source).to be_include 'if current_user?'
      expect(encoded_source).to be_include '"User"'
      expect(encoded_source).to be_include 'error_message'
      expect(encoded_source).to be_include 'form_for @user do |f|'
      expect(encoded_source.scan("end\n").length).to eq 3
      expect(encoded_source).not_to be_include '%p'
      expect(encoded_source).not_to be_include 'strong'
      expect(encoded_source).not_to be_include '#error'
      expect(encoded_source).not_to be_include 'Test'
      expect(encoded_source).not_to be_include '.form-actions'
    end
  end
end
