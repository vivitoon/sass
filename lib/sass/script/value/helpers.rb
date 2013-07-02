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

    # Construct a Sass Color from a hex color string.
    #
    # @since `3.3.0`
    # @param value [::String] A string representing a hex color.
    #                         The leading hash ("#") is optional.
    # @param alpha [::Number] The alpha channel. A number between 0 and 1.
    # @return [Sass::Script::Value::Color] the color object
    def hex_color(value, alpha = nil)
      Color.from_hex(value, alpha)
    end

    # Construct a Sass Color from hsl values.
    #
    # @since `3.3.0`
    # @param hue [::Number] The hue of the color in degrees. A number generally
    #                       between 0 and 360, but it must only be non-negative.
    # @param saturation [::Number] The saturation of the color.
    #                              Must be between 0 and 100 inclusive.
    # @param lightness [::Number] The lightness of the color.
    #                             Must be between 0 and 100 inclusive.
    # @param alpha [::Number] The alpha channel. A number between 0 and 1.
    #
    # @return [Sass::Script::Value::Color] the color object
    def hsl_color(hue, saturation, lightness, alpha = nil)
      attrs = {:hue => hue, :saturation => saturation, :lightness => lightness}
      attrs[:alpha] = alpha if alpha
      Color.new(attrs)
    end

    # @private
    VALID_UNIT = /#{Sass::SCSS::RX::NMSTART}#{Sass::SCSS::RX::NMCHAR}|%*/

    # Construct a Sass Number from a ruby number.
    #
    # @since `3.3.0`
    # @param number [::Number] A numeric value.
    # @param unit_string [::String] A unit string of the form
    #   `numeral_unit1 * numeral_unit2 ... / denominator_unit1 * denominator_unit2 ...`
    #   this is the same format that is returned by {Sass::Script::Value::Number#unit_str the `unit_str` method}
    #
    # @see Sass::Script::Value::Number#unit_str
    #
    # @return [Sass::Script::Value::Number] The sass number representing the given ruby number.
    def number(number, unit_string = nil)
      numerator_units = Sass::Script::Value::Number::NO_UNITS
      denominator_units = Sass::Script::Value::Number::NO_UNITS
      if unit_string
        num_over_denominator = unit_string.split(/ *\/ */)
        unless (1..2).include?(num_over_denominator.size)
          raise ArgumentError.new("Malformed unit string: #{unit_string}")
        end
        numerator_units = num_over_denominator[0].split(/ *\* */)
        denominator_units = (num_over_denominator[1] || "").split(/ *\* */)
        unless numerator_units.size >= 1 && numerator_units.all? {|unit| unit =~ VALID_UNIT }
          raise ArgumentError.new("Malformed numerator in unit string: #{unit_string}")
        end
        unless denominator_units.all? {|unit| unit =~ VALID_UNIT }
          raise ArgumentError.new("Malformed denominator in unit string: #{unit_string}")
        end
      end
      Number.new(number, numerator_units, denominator_units)
    end

    # @since `3.3.0`
    # @overload space_list(*elements)
    #   Create a space-separated list from the arguments given.
    #   @param elements [Array<Sass::Script::Value::Base>] Each argument will be a list element.
    #   @return [Sass::Script::Value::List] The space separated list.
    #
    # @overload space_list(array)
    #   Create a space-separated list from the array given.
    #   @param array [Array<Sass::Script::Value::Base>] A ruby array of Sass values to make into a list.
    #   @return [Sass::Script::Value::List] The space separated list.
    def space_list(*elements)
      if elements.size == 1 && elements.first.is_a?(Array)
        elements = elements.first
      end
      Sass::Script::Value::List.new(elements, :space)
    end

    # @since `3.3.0`
    # @overload comma_list(*elements)
    #   Create a comma-separated list from the arguments given.
    #   @param elements [Array<Sass::Script::Value::Base>] Each argument will be a list element.
    #   @return [Sass::Script::Value::List] The comma separated list.
    #
    # @overload comma_list(array)
    #   Create a comma-separated list from the array given.
    #   @param array [Array<Sass::Script::Value::Base>] A ruby array of Sass values to make into a list.
    #   @return [Sass::Script::Value::List] The comma separated list.
    def comma_list(*elements)
      if elements.size == 1 && elements.first.is_a?(Array)
        elements = elements.first
      end
      Sass::Script::Value::List.new(elements, :comma)
    end
  end
end
