# frozen_string_literal: true

module Sidekiq
  module Crond
    # Support for helpers methods
    module Support
      class << self
        # constantize from rails https://github.com/rails/rails/blob/f33d52c95217212cbacc8d5e44b5a8e3cdc6f5b3/activesupport/lib/active_support/inflector/methods.rb#L271
        def constantize(camel_cased_word)
          names = camel_cased_word.split('::')

          # Trigger a built-in NameError exception including the ill-formed constant in the message.
          Object.const_get(camel_cased_word) if names.empty?

          # Remove the first blank element in case of '::ClassName' notation.
          names.shift if names.size > 1 && names.first.empty?

          names.inject(Object) do |constant, name|
            if constant == Object
              constant.const_get(name)
            else
              candidate = constant.const_get(name)
              next candidate if constant.const_defined?(name, false)
              next candidate unless Object.const_defined?(name)

              # Go down the ancestors to check if it is owned directly. The check
              # stops when we reach Object or the end of ancestors tree.
              constant = constant.ancestors.each_with_object(constant) do |ancestor, const|
                break const    if ancestor == Object
                break ancestor if ancestor.const_defined?(name, false)
              end

              # owner is in Object, so raise
              constant.const_get(name, false)
            end
          end
        end
      end
    end
  end
end
