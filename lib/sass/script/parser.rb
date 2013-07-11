require 'sass/script/lexer'

module Sass
  module Script
    # The parser for SassScript.
    # It parses a string of code into a tree of {Script::Tree::Node}s.
    class Parser
      # The line number of the parser's current position.
      #
      # @return [Fixnum]
      def line
        @lexer.line
      end

      # The column number of the parser's current position.
      #
      # @return [Fixnum]
      def offset
        @lexer.offset
      end

      # @param str [String, StringScanner] The source text to parse
      # @param line [Fixnum] The line on which the SassScript appears.
      #   Used for error reporting and sourcemap building
      # @param offset [Fixnum] The character (not byte) offset in the line on which the SassScript appears.
      #   Used for error reporting and sourcemap building
      # @param options [{Symbol => Object}] An options hash;
      #   see {file:SASS_REFERENCE.md#sass_options the Sass options documentation}
      def initialize(str, line, offset, options = {})
        @options = options
        @lexer = lexer_class.new(str, line, offset, options)
      end

      # Parses a SassScript expression within an interpolated segment (`#{}`).
      # This means that it stops when it comes across an unmatched `}`,
      # which signals the end of an interpolated segment,
      # it returns rather than throwing an error.
      #
      # @return [Script::Tree::Node] The root node of the parse tree
      # @raise [Sass::SyntaxError] if the expression isn't valid SassScript
      def parse_interpolated
        expr = assert_expr :expr
        assert_tok :end_interpolation
        expr.options = @options
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses a SassScript expression.
      #
      # @return [Script::Tree::Node] The root node of the parse tree
      # @raise [Sass::SyntaxError] if the expression isn't valid SassScript
      def parse
        expr = assert_expr :expr
        assert_done
        expr.options = @options
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses a SassScript expression,
      # ending it when it encounters one of the given identifier tokens.
      #
      # @param tokens [#include?(String)] A set of strings that delimit the expression.
      # @return [Script::Tree::Node] The root node of the parse tree
      # @raise [Sass::SyntaxError] if the expression isn't valid SassScript
      def parse_until(tokens)
        @stop_at = tokens
        expr = assert_expr :expr
        assert_done
        expr.options = @options
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses the argument list for a mixin include.
      #
      # @return [(Array<Script::Tree::Node>, {String => Script::Tree::Node}, Script::Tree::Node)]
      #   The root nodes of the positional arguments, keyword arguments, and
      #   splat argument. Keyword arguments are in a hash from names to values.
      # @raise [Sass::SyntaxError] if the argument list isn't valid SassScript
      def parse_mixin_include_arglist
        args, keywords = [], {}
        if try_tok(:lparen)
          args, keywords, splat = mixin_arglist || [[], {}]
          assert_tok(:rparen)
        end
        assert_done

        args.each {|a| a.options = @options}
        keywords.each {|k, v| v.options = @options}
        splat.options = @options if splat
        return args, keywords, splat
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses the argument list for a mixin definition.
      #
      # @return [(Array<Script::Tree::Node>, Script::Tree::Node)]
      #   The root nodes of the arguments, and the splat argument.
      # @raise [Sass::SyntaxError] if the argument list isn't valid SassScript
      def parse_mixin_definition_arglist
        args, splat = defn_arglist!(false)
        assert_done

        args.each do |k, v|
          k.options = @options
          v.options = @options if v
        end
        splat.options = @options if splat
        return args, splat
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses the argument list for a function definition.
      #
      # @return [(Array<Script::Tree::Node>, Script::Tree::Node)]
      #   The root nodes of the arguments, and the splat argument.
      # @raise [Sass::SyntaxError] if the argument list isn't valid SassScript
      def parse_function_definition_arglist
        args, splat = defn_arglist!(true)
        assert_done

        args.each do |k, v|
          k.options = @options
          v.options = @options if v
        end
        splat.options = @options if splat
        return args, splat
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parse a single string value, possibly containing interpolation.
      # Doesn't assert that the scanner is finished after parsing.
      #
      # @return [Script::Tree::Node] The root node of the parse tree.
      # @raise [Sass::SyntaxError] if the string isn't valid SassScript
      def parse_string
        unless (peek = @lexer.peek) &&
            (peek.type == :string ||
            (peek.type == :funcall && peek.value.downcase == 'url'))
          lexer.expected!("string")
        end

        expr = assert_expr :funcall
        expr.options = @options
        @lexer.unpeek!
        expr
      rescue Sass::SyntaxError => e
        e.modify_backtrace :line => @lexer.line, :filename => @options[:filename]
        raise e
      end

      # Parses a SassScript expression.
      #
      # @overload parse(str, line, offset, filename = nil)
      # @return [Script::Tree::Node] The root node of the parse tree
      # @see Parser#initialize
      # @see Parser#parse
      def self.parse(*args)
        new(*args).parse
      end

      PRECEDENCE = [
        :comma, :single_eq, :space, :or, :and,
        [:eq, :neq],
        [:gt, :gte, :lt, :lte],
        [:plus, :minus],
        [:times, :div, :mod],
      ]

      ASSOCIATIVE = [:plus, :times]

      class << self
        # Returns an integer representing the precedence
        # of the given operator.
        # A lower integer indicates a looser binding.
        #
        # @private
        def precedence_of(op)
          PRECEDENCE.each_with_index do |e, i|
            return i if Array(e).include?(op)
          end
          raise "[BUG] Unknown operator #{op}"
        end

        # Returns whether or not the given operation is associative.
        #
        # @private
        def associative?(op)
          ASSOCIATIVE.include?(op)
        end

        private

        # Defines a simple left-associative production.
        # name is the name of the production,
        # sub is the name of the production beneath it,
        # and ops is a list of operators for this precedence level
        def production(name, sub, *ops)
          class_eval <<RUBY, __FILE__, __LINE__ + 1
            def #{name}
              interp = try_ops_after_interp(#{ops.inspect}, #{name.inspect}) and return interp
              return unless e = #{sub}
              while tok = try_tok(#{ops.map {|o| o.inspect}.join(', ')})
                if interp = try_op_before_interp(tok, e)
                  return interp unless other_interp = try_ops_after_interp(#{ops.inspect}, #{name.inspect}, interp)
                  return other_interp
                end

                start_pos = source_position
                e = node(Tree::Operation.new(e, assert_expr(#{sub.inspect}), tok.type), start_pos)
              end
              e
            end
RUBY
        end

        def unary(op, sub)
          class_eval <<RUBY, __FILE__, __LINE__ + 1
            def unary_#{op}
              return #{sub} unless tok = try_tok(:#{op})
              interp = try_op_before_interp(tok) and return interp
              start_pos = source_position
              node(Tree::UnaryOperation.new(assert_expr(:unary_#{op}), :#{op}), start_pos)
            end
RUBY
        end
      end

      private

      def source_position
        Sass::Source::Position.new(line, offset)
      end

      def range(start_pos, end_pos=source_position)
        Sass::Source::Range.new(start_pos, end_pos, @options[:filename], @options[:importer])
      end

      # @private
      def lexer_class; Lexer; end

      def expr
        interp = try_ops_after_interp([:comma], :expr) and return interp
        start_pos = source_position
        e = interpolation
        return unless e
        list = node(Sass::Script::Tree::ListLiteral.new([e], :comma), start_pos)
        while (tok = try_tok(:comma))
          if (interp = try_op_before_interp(tok, list))
            other_interp = try_ops_after_interp([:comma], :expr, interp)
            return interp unless other_interp
            return other_interp
          end
          list.elements << assert_expr(:interpolation)
        end
        list.elements.size == 1 ? list.elements.first : list
      end

      production :equals, :interpolation, :single_eq

      def try_op_before_interp(op, prev = nil)
        return unless @lexer.peek && @lexer.peek.type == :begin_interpolation
        wb = @lexer.whitespace?(op)
        str = literal_node(Script::Value::String.new(Lexer::OPERATORS_REVERSE[op.type]), op.source_range)
        interp = node(
          Script::Tree::Interpolation.new(prev, str, nil, wb, !:wa, :originally_text),
          (prev || str).source_range.start_pos)
        interpolation(interp)
      end

      def try_ops_after_interp(ops, name, prev = nil)
        return unless @lexer.after_interpolation?
        op = try_tok(*ops)
        return unless op
        interp = try_op_before_interp(op, prev) and return interp

        wa = @lexer.whitespace?
        str = literal_node(Script::Value::String.new(Lexer::OPERATORS_REVERSE[op.type]), op.source_range)
        str.line = @lexer.line
        interp = node(
          Script::Tree::Interpolation.new(prev, str, assert_expr(name), !:wb, wa, :originally_text),
          (prev || str).source_range.start_pos)
        return interp
      end

      def interpolation(first = space)
        e = first
        while (interp = try_tok(:begin_interpolation))
          wb = @lexer.whitespace?(interp)
          line = @lexer.line
          mid = parse_interpolated
          wa = @lexer.whitespace?
          e = node(
            Script::Tree::Interpolation.new(e, mid, space, wb, wa),
            (e || mid).source_range.start_pos)
        end
        e
      end

      def space
        start_pos = source_position
        e = or_expr
        return unless e
        arr = [e]
        while (e = or_expr)
          arr << e
        end
        arr.size == 1 ? arr.first : node(Sass::Script::Tree::ListLiteral.new(arr, :space), start_pos)
      end

      production :or_expr, :and_expr, :or
      production :and_expr, :eq_or_neq, :and
      production :eq_or_neq, :relational, :eq, :neq
      production :relational, :plus_or_minus, :gt, :gte, :lt, :lte
      production :plus_or_minus, :times_div_or_mod, :plus, :minus
      production :times_div_or_mod, :unary_plus, :times, :div, :mod

      unary :plus, :unary_minus
      unary :minus, :unary_div
      unary :div, :unary_not # For strings, so /foo/bar works
      unary :not, :ident

      def ident
        return funcall unless @lexer.peek && @lexer.peek.type == :ident
        return if @stop_at && @stop_at.include?(@lexer.peek.value)

        name = @lexer.next
        if (color = Sass::Script::Value::Color::COLOR_NAMES[name.value.downcase])
          return literal_node(Sass::Script::Value::Color.new(color), name.source_range)
        end
        literal_node(Script::Value::String.new(name.value, :identifier), name.source_range)
      end

      def funcall
        tok = try_tok(:funcall)
        return raw unless tok
        args, keywords, splat = fn_arglist || [[], {}]
        assert_tok(:rparen)
        node(Script::Tree::Funcall.new(tok.value, args, keywords, splat),
          tok.source_range.start_pos, source_position)
      end

      def defn_arglist!(must_have_parens)
        if must_have_parens
          assert_tok(:lparen)
        else
          return [], nil unless try_tok(:lparen)
        end
        return [], nil if try_tok(:rparen)

        res = []
        splat = nil
        must_have_default = false
        loop do
          c = assert_tok(:const)
          var = node(Script::Tree::Variable.new(c.value), c.source_range)
          if try_tok(:colon)
            val = assert_expr(:space)
            must_have_default = true
          elsif must_have_default
            raise SyntaxError.new("Required argument #{var.inspect} must come before any optional arguments.")
          elsif try_tok(:splat)
            splat = var
            break
          end
          res << [var, val]
          break unless try_tok(:comma)
        end
        assert_tok(:rparen)
        return res, splat
      end

      def fn_arglist
        arglist(:equals, "function argument")
      end

      def mixin_arglist
        arglist(:interpolation, "mixin argument")
      end

      def arglist(subexpr, description)
        e = send(subexpr)
        return unless e

        args = []
        keywords = {}
        loop do
          if @lexer.peek && @lexer.peek.type == :colon
            name = e
            @lexer.expected!("comma") unless name.is_a?(Tree::Variable)
            assert_tok(:colon)
            value = assert_expr(subexpr, description)

            if keywords[name.underscored_name]
              raise SyntaxError.new("Keyword argument \"#{name.to_sass}\" passed more than once")
            end

            keywords[name.underscored_name] = value
          else
            if !keywords.empty?
              raise SyntaxError.new("Positional arguments must come before keyword arguments.")
            end

            return args, keywords, e if try_tok(:splat)
            args << e
          end

          return args, keywords unless try_tok(:comma)
          e = assert_expr(subexpr, description)
        end
      end

      def raw
        tok = try_tok(:raw)
        return special_fun unless tok
        literal_node(Script::Value::String.new(tok.value), tok.source_range)
      end

      def special_fun
        start_pos = source_position
        tok = try_tok(:special_fun)
        return paren unless tok
        first = literal_node(Script::Value::String.new(tok.value.first),
          start_pos, start_pos.after(tok.value.first))
        Sass::Util.enum_slice(tok.value[1..-1], 2).inject(first) do |l, (i, r)|
          end_pos = i.source_range.end_pos
          end_pos = end_pos.after(r) if r
          node(
            Script::Tree::Interpolation.new(
              l, i,
              r && literal_node(Script::Value::String.new(r),
                i.source_range.end_pos, end_pos),
              false, false),
            start_pos, end_pos)
        end
      end

      def paren
        return variable unless try_tok(:lparen)
        was_in_parens = @in_parens
        @in_parens = true
        start_pos = source_position
        e = expr
        end_pos = source_position
        assert_tok(:rparen)
        return e || node(Sass::Script::Tree::ListLiteral.new([], :space), start_pos, end_pos)
      ensure
        @in_parens = was_in_parens
      end

      def variable
        start_pos = source_position
        c = try_tok(:const)
        return string unless c
        node(Tree::Variable.new(*c.value), start_pos)
      end

      def string
        first = try_tok(:string)
        return number unless first
        str = literal_node(first.value, first.source_range)
        return str unless try_tok(:begin_interpolation)
        mid = parse_interpolated
        last = assert_expr(:string)
        node(Tree::StringInterpolation.new(str, mid, last), first.source_range.start_pos)
      end

      def number
        tok = try_tok(:number)
        return literal unless tok
        num = tok.value
        num.original = num.to_s unless @in_parens
        literal_node(num, tok.source_range.start_pos)
      end

      def literal
        (t = try_tok(:color, :bool, :null)) && (return literal_node(t.value, t.source_range))
      end

      # It would be possible to have unified #assert and #try methods,
      # but detecting the method/token difference turns out to be quite expensive.

      EXPR_NAMES = {
        :string => "string",
        :default => "expression (e.g. 1px, bold)",
        :mixin_arglist => "mixin argument",
        :fn_arglist => "function argument",
      }

      def assert_expr(name, expected = nil)
        (e = send(name)) && (return e)
        @lexer.expected!(expected || EXPR_NAMES[name] || EXPR_NAMES[:default])
      end

      def assert_tok(*names)
        (t = try_tok(*names)) && (return t)
        @lexer.expected!(names.map {|tok| Lexer::TOKEN_NAMES[tok] || tok}.join(" or "))
      end

      def try_tok(*names)
        peeked =  @lexer.peek
        peeked && names.include?(peeked.type) && @lexer.next
      end

      def assert_done
        return if @lexer.done?
        @lexer.expected!(EXPR_NAMES[:default])
      end

      # @overload node(value, source_range)
      #   @param value [Sass::Script::Value::Base]
      #   @param source_range [Sass::Source::Range]
      # @overload node(value, start_pos, end_pos = source_position)
      #   @param value [Sass::Script::Value::Base]
      #   @param start_pos [Sass::Source::Position]
      #   @param end_pos [Sass::Source::Position]
      def literal_node(value, source_range_or_start_pos, end_pos = source_position)
        node(Sass::Script::Tree::Literal.new(value), source_range_or_start_pos, end_pos)
      end

      # @overload node(node, source_range)
      #   @param node [Sass::Script::Tree::Node]
      #   @param source_range [Sass::Source::Range]
      # @overload node(node, start_pos, end_pos = source_position)
      #   @param node [Sass::Script::Tree::Node]
      #   @param start_pos [Sass::Source::Position]
      #   @param end_pos [Sass::Source::Position]
      def node(node, source_range_or_start_pos, end_pos = source_position)
        source_range =
          if source_range_or_start_pos.is_a?(Sass::Source::Range)
            source_range_or_start_pos
          else
            range(source_range_or_start_pos, end_pos)
          end

        node.line = source_range.start_pos.line
        node.source_range = source_range
        node.filename = @options[:filename]
        node
      end
    end
  end
end
