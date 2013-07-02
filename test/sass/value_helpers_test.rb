#!/usr/bin/env ruby
require File.dirname(__FILE__) + '/../test_helper'

class ValueHelpersTest < Test::Unit::TestCase
  include Sass::Script
  include Sass::Script::Value::Helpers

  def test_bool
    assert_same Value::Bool::TRUE, bool(true)
    assert_same Value::Bool::FALSE, bool(false)
    assert_same Value::Bool::FALSE, bool(nil)
    assert_same Value::Bool::TRUE, bool(Object.new)
  end

  def test_hex_color
    color_without_hash = hex_color("FF007F")
    assert_equal 255, color_without_hash.red
    assert_equal 0, color_without_hash.green
    assert_equal 127, color_without_hash.blue
    assert_equal 1, color_without_hash.alpha

    color_with_hash = hex_color("#FF007F")
    assert_equal 255, color_with_hash.red
    assert_equal 0, color_with_hash.green
    assert_equal 127, color_with_hash.blue
    assert_equal 1, color_with_hash.alpha

    color_with_alpha = hex_color("FF007F", 0.5)
    assert_equal 0.5, color_with_alpha.alpha

    assert_raises ArgumentError do
      hex_color("FF007F", 50)
    end
  end

  def test_hsl_color
    no_alpha = hsl_color(1, 0.5, 1)
    assert_equal 1, no_alpha.hue
    assert_equal 0.5, no_alpha.saturation
    assert_equal 1, no_alpha.lightness
    assert_equal 1, no_alpha.alpha

    has_alpha = hsl_color(1, 0.5, 1, 0.5)
    assert_equal 1, has_alpha.hue
    assert_equal 0.5, has_alpha.saturation
    assert_equal 1, has_alpha.lightness
    assert_equal 0.5, has_alpha.alpha
  end

  def test_number
    n = number(1);
    assert_equal 1, n.value
    assert_equal "1", n.to_sass
    assert_raise ArgumentError do
      number("asdf")
    end
  end

  def test_number_with_units
    # single unit
    n = number(1, "px");
    assert_equal 1, n.value
    assert_equal "1px", n.to_sass

    # single numerator and denominator units
    ratio = number(1, "px/em");
    assert_equal "1px/em", ratio.to_sass

    # many numerator and denominator units
    complex = number(1, "px*in/em*%");
    assert_equal "1#{['px','in'].sort.join("*")}/#{['em','%'].sort.join("*")}", complex.to_sass

    # many numerator and denominator units with spaces
    complex = number(1, "px * in / em * %");
    assert_equal "1#{['px','in'].sort.join("*")}/#{['em','%'].sort.join("*")}", complex.to_sass
  end

  def test_space_list
    l = space_list(number(1, "px"), hex_color("#f71"))
    l.options = {}
    assert_kind_of Sass::Script::Value::List, l
    assert_equal "1px #ff7711", l.to_sass

    l2 = space_list([number(1, "px"), hex_color("#f71")])
    l2.options = {}
    assert_kind_of Sass::Script::Value::List, l2
    assert_equal "1px #ff7711", l2.to_sass
  end

  def test_comma_list
    l = comma_list(number(1, "px"), hex_color("#f71"))
    l.options = {}
    assert_kind_of Sass::Script::Value::List, l
    assert_equal "1px, #ff7711", l.to_sass

    l2 = comma_list([number(1, "px"), hex_color("#f71")])
    l2.options = {}
    assert_kind_of Sass::Script::Value::List, l2
    assert_equal "1px, #ff7711", l2.to_sass
  end

  def test_null
    assert_kind_of Sass::Script::Value::Null, null
  end

  def test_string
    s = string("sassy string")
    s.options = {}
    assert_kind_of Sass::Script::Value::String, s
    assert_equal "sassy string", s.value
    assert_equal :string, s.type
    assert_equal %q{"sassy string"}, s.to_sass
  end

  def test_identifier
    s = identifier("a-sass-ident")
    s.options = {}
    assert_kind_of Sass::Script::Value::String, s
    assert_equal "a-sass-ident", s.value
    assert_equal :identifier, s.type
    assert_equal %q{a-sass-ident}, s.to_sass
  end
end
