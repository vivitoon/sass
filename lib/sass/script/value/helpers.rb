module Sass::Script::Value
  # Provides helper functions for creating sass values from within ruby methods
  module Helpers

    # Construct a Sass Boolean value.
    #
    # This method returns boolean constants instead of creating a new value object
    # with each call.
    #
    # @since `3.3.0`
    # @return [Sass::Script::Value::Bool] whether the ruby value is truthy.
    def bool(value)
      Bool.new(value)
    end
  end
end
