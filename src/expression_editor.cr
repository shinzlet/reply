require "./term_cursor"
require "./term_size"

module Reply
  # The `ExpressionEditor` allows to edit and display an expression.
  #
  # Its main task is to provide the display of the prompt and a multiline expression within
  # the term bounds, and ensure the correspondence between the cursor on screen and the cursor on the expression.
  #
  # Usage example:
  # ```
  # # new editor:
  # @editor = ExpressionEditor.new(
  #   prompt: ->(expr_line_number : Int32) { "prompt>" }
  # )
  #
  # # edit some code:
  # @editor.update do
  #   @editor << %(puts "World")
  #
  #   insert_new_line(indent: 1)
  #   @editor << %(puts "!")
  # end
  #
  # # move cursor:
  # @editor.move_cursor_up
  # 4.times { @editor.move_cursor_left }
  #
  # # edit:
  # @editor.update do
  #   @editor << "Hello "
  # end
  #
  # @editor.end_editing
  #
  # @editor.expression # => %(puts "Hello World"\n  puts "!")
  # puts "=> ok"
  #
  # # clear and restart edition:
  # @editor.prompt_next
  # ```
  #
  # The above displays:
  # ```
  # prompt>puts "Hello World"
  # prompt>  puts "!"
  # => ok
  # prompt>
  # ```
  #
  # Methods that modify the expression should be placed inside an `update` so the screen can be refreshed taking in account
  # the adding or removing of lines, and doesn't boilerplate the display.
  class ExpressionEditor
    getter lines : Array(String) = [""]
    getter expression : String? { lines.join('\n') }
    getter expression_height : Int32? { lines.sum { |l| line_height(l) } }
    getter colorized_lines : Array(String)? do
      color? ? @highlight.call(self.expression).split('\n') : lines
    end

    property? color = true
    property output : IO = STDOUT

    # Tracks the cursor position relatively to the expression's lines, (y=0 corresponds to the first line and x=0 the first char)
    # This position is independent of text wrapping so its position will not match to real cursor on screen.
    #
    # `|` : cursor position
    #
    # ```
    # prompt>def very_looo
    # ooo|ng_name            <= wrapping
    # prompt>  bar
    # prompt>end
    # ```
    # For example here the cursor position is x=16, y=0, but real cursor is at x=3,y=1 from the beginning of expression.
    getter x = 0
    getter y = 0

    # The editor height, if not set (`nil`), equal to term height.
    setter height : Int32? = nil

    # The editor width, if not set (`nil`), equal to term width.
    setter width : Int32? = nil

    @prompt : Int32, Bool -> String
    @prompt_size : Int32

    @scroll_offset = 0
    @header_height = 0

    @header : IO, Int32 -> Int32 = ->(io : IO, previous_height : Int32) { 0 }
    @highlight = ->(code : String) { code }

    # Creates a new `ExpressionEditor` with the given *prompt*.
    def initialize(&@prompt : Int32, Bool -> String)
      @prompt_size = @prompt.call(0, false).size # uncolorized size

      at_exit { @output.print Term::Cursor.show }
    end

    # Sets a `Proc` allowing to display a header above the prompt. (used by auto-completion)
    #
    # *io*: The IO in which the header should be displayed.
    # *previous_hight*: Previous header height, useful to keep a header size constant.
    # Should returns the exact *height* printed in the io.
    def set_header(&@header : IO, Int32 -> Int32)
    end

    # Sets the `Proc` to highlight the expression.
    def set_highlight(&@highlight : String -> String)
    end

    private def move_cursor(x, y)
      @x += x
      @y += y
    end

    private def move_real_cursor(x, y)
      @output.print Term::Cursor.move(x, -y)
    end

    private def move_abs_cursor(@x, @y)
    end

    private def reset_cursor
      @x = @y = 0
    end

    def current_line
      @lines[@y]
    end

    def previous_line?
      if @y > 0
        @lines[@y - 1]
      end
    end

    def next_line?
      @lines[@y + 1]?
    end

    def cursor_on_last_line?
      (@y == @lines.size - 1)
    end

    def expression_before_cursor(x = @x, y = @y)
      String.build do |io|
        @lines[...y].each { |line| io << line << '\n' }
        io << @lines[y][...x]
      end
    end

    # Following functions modifies the expression, they should be called inside
    # an `update` block to see the changes in the screen: #

    # Should be called inside an `update`.
    def previous_line=(line)
      @lines[@y - 1] = line
      @expression = @expression_height = @colorized_lines = nil
    end

    # Should be called inside an `update`.
    def current_line=(line)
      @lines[@y] = line
      @expression = @expression_height = @colorized_lines = nil
    end

    # Should be called inside an `update`.
    def next_line=(line)
      @lines[@y + 1] = line
      @expression = @expression_height = @colorized_lines = nil
    end

    # Should be called inside an `update`.
    def delete_line(y)
      @lines.delete_at(y)
      @expression = @expression_height = @colorized_lines = nil
    end

    # Should be called inside an `update`.
    def clear_expression
      @lines.clear << ""
      @expression = @expression_height = @colorized_lines = nil
    end

    # Should be called inside an `update`.
    #
    # If *char* is `\n` or `\r`, inserts a new line with indent 0.
    # Does nothing if the char is an `ascii_control?`.
    def <<(char : Char) : self
      return insert_new_line(0) if char.in? '\n', '\r'
      return self if char.ascii_control?

      if @x >= current_line.size
        self.current_line = current_line + char
      else
        self.current_line = current_line.insert(@x, char)
      end

      move_cursor(x: +1, y: 0)
      self
    end

    # Should be called inside an `update`.
    def <<(str : String) : self
      str.each_char do |ch|
        self << ch
      end
      self
    end

    # Should be called inside an `update`.
    def insert_new_line(indent)
      case @x
      when current_line.size
        @lines.insert(@y + 1, "  "*indent)
      when .< current_line.size
        @lines.insert(@y + 1, "  "*indent + current_line[@x..])
        self.current_line = current_line[...@x]
      end

      @expression = @expression_height = @colorized_lines = nil
      move_abs_cursor(x: indent*2, y: @y + 1)
      self
    end

    # Should be called inside an `update`.
    def delete
      case @x
      when current_line.size
        if next_line = next_line?
          self.current_line = current_line + next_line

          delete_line(@y + 1)
        end
      when .< current_line.size
        self.current_line = current_line.delete_at(@x)
      end
    end

    # Should be called inside an `update`.
    def back
      case @x
      when 0
        if prev_line = previous_line?
          self.previous_line = prev_line + current_line

          move_cursor(x: prev_line.size, y: -1)
          delete_line(@y + 1)
        end
      when .> 0
        self.current_line = current_line.delete_at(@x - 1)
        move_cursor(x: -1, y: 0)
      end
    end

    # End modifying functions. #

    # Gives the size of the last part of the line when it's wrapped
    #
    # prompt>def very_looo
    # ooooooooong              <= last part
    # prompt>  bar
    # prompt>end
    #
    # e.g. here "ooooooooong".size = 10
    private def last_part_size(line_size)
      (@prompt_size + line_size) % self.width
    end

    # Returns the height of this line, (1 on common lines, more on wrapped lines):
    private def line_height(line)
      1 + (@prompt_size + line.size) // self.width
    end

    # The editor width, if not set (`nil`), equal to term width.
    def width
      @width || Term::Size.width
    end

    # The editor height, if not set (`nil`), equal to term height.
    def height
      @height || Term::Size.height
    end

    # Returns the max height that could take an expression on screen.
    #
    # The expression scrolls if it's higher than epression_max_height.
    private def epression_max_height
      self.height - @header_height
    end

    def move_cursor_left(allow_scrolling = true)
      case @x
      when 0
        # Wrap the cursor at the end of the previous line:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt>def very_looo
        # ooooooooong*
        # prompt>| bar
        # prompt>end
        # ```
        if prev_line = previous_line?
          scroll_up_if_needed if allow_scrolling

          # Wrap real cursor:
          size_of_last_part = last_part_size(prev_line.size)
          move_real_cursor(x: -@prompt_size + size_of_last_part, y: -1)

          # Wrap cursor:
          move_cursor(x: prev_line.size, y: -1)
        end
      when .> 0
        # Move the cursor left, wrap the real cursor if needed:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt>def very_looo*
        # |oooooooong
        # prompt>  bar
        # prompt>end
        # ```
        if last_part_size(@x) == 0
          scroll_up_if_needed if allow_scrolling
          move_real_cursor(x: self.width + 1, y: -1)
        else
          move_real_cursor(x: -1, y: 0)
        end
        move_cursor(x: -1, y: 0)
      end
    end

    def move_cursor_right(allow_scrolling = true)
      case @x
      when current_line.size
        # Wrap the cursor at the beginning of the next line:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt>def very_looo
        # ooooooooong|
        # prompt>* bar
        # prompt>end
        # ```
        if next_line?
          scroll_down_if_needed if allow_scrolling

          # Wrap real cursor:
          size_of_last_part = last_part_size(current_line.size)
          move_real_cursor(x: -size_of_last_part + @prompt_size, y: +1)

          # Wrap cursor:
          move_cursor(x: -current_line.size, y: +1)
        end
      when .< current_line.size
        # Move the cursor right, wrap the real cursor if needed:
        #
        # `|`: cursor pos
        # `*`: wanted pos
        #
        # ```
        # prompt>def very_looo|
        # *oooooooong
        # prompt>  bar
        # prompt>end
        # ```
        if last_part_size(@x) == (self.width - 1)
          scroll_down_if_needed if allow_scrolling

          move_real_cursor(x: -self.width, y: +1)
        else
          move_real_cursor(x: +1, y: 0)
        end

        # move cursor right
        move_cursor(x: +1, y: 0)
      end
    end

    def move_cursor_up
      scroll_up_if_needed

      if (@prompt_size + @x) >= self.width
        if @x >= self.width
          # Here, we have:
          # ```
          # prompt>def *very_looo
          # ooooooooooo|ooooooooo
          # ooooooooong
          # prompt>  bar
          # prompt>end
          # ```
          # So we need only to move real cursor up
          # and move back @x by term-width.
          #
          move_real_cursor(x: 0, y: -1)
          move_cursor(x: -self.width, y: 0)
        else
          # Here, we have:
          # ```
          # prompt>*def very_looo
          # ooo|ooooooooooooooooo
          # ooooooooong
          # prompt>  bar
          # prompt>end
          # ```
          #
          move_real_cursor(x: self.width - @x, y: -1)
          move_cursor(x: 0 - @x, y: 0)
        end

        true
      elsif prev_line = previous_line?
        # Here, there are a previous line in which we can move up, we want to
        # move on the last part of the previous line:
        size_of_last_part = last_part_size(prev_line.size)

        if size_of_last_part < @prompt_size + @x
          # ```
          # prompt>def very_looo
          # oooooooooooooooooooo
          # ong*                  <= last part
          # prompt>  ba|aar
          # prompt>end
          # ```
          move_real_cursor(x: -@x - @prompt_size + size_of_last_part, y: -1)
          move_abs_cursor(x: prev_line.size, y: @y - 1)
        else
          # ```
          # prompt>def very_looo
          # oooooooooooooooooooo
          # ooooooooooo*ooong    <= last part
          # prompt>  ba|aar
          # prompt>end
          # ```
          move_real_cursor(x: 0, y: -1)
          x = prev_line.size - size_of_last_part + @prompt_size + @x
          move_abs_cursor(x: x, y: @y - 1)
        end
        true
      else
        false
      end
    end

    def move_cursor_down
      scroll_down_if_needed

      size_of_last_part = last_part_size(current_line.size)
      real_x = last_part_size(@x)

      remaining = current_line.size - @x

      if remaining > size_of_last_part
        # on middle
        if remaining > self.width
          # Here, there are enough remaining to just move down
          # ```
          # prompt>def very|_loooo
          # ooooooooooooooo*oooooo
          # ong
          # prompt>  bar
          # prompt>end
          # ```
          #
          move_real_cursor(x: 0, y: +1)
          move_cursor(x: self.width, y: 0)
        else
          # Here, we goes to end of current line:
          # ```
          # prompt>def very_loooo
          # ooooooooooooooo|ooooo
          # ong*
          # prompt>  bar
          # prompt>end
          # ```
          move_real_cursor(x: -real_x + size_of_last_part, y: +1)
          move_abs_cursor(x: current_line.size, y: @y)
        end
        true
      elsif next_line = next_line?
        case real_x
        when .< @prompt_size
          # Here, we are behind the prompt so we want goes to the beginning of the next line:
          # ```
          # prompt>def very_loooo
          # ooooooooooooooooooooo
          # ong|
          # prompt>* bar
          # prompt>end
          # ```
          move_real_cursor(x: -real_x + @prompt_size, y: +1)
          move_abs_cursor(x: 0, y: @y + 1)
        when .< @prompt_size + next_line.size
          # Here, we can just move down on the next line:
          # ```
          # prompt>def very_loooo
          # ooooooooooooooooooooo
          # ooooooooong|
          # prompt>  ba*r
          # prompt>end
          # ```
          move_real_cursor(x: 0, y: +1)
          move_abs_cursor(x: real_x - @prompt_size, y: @y + 1)
        else
          # Finally, here, we want to move at end of the next line:
          # ```
          # prompt>def very_loooo
          # ooooooooooooooooooooo
          # ooooooooooooooong|
          # prompt>  bar*
          # prompt>end
          # ```
          x = real_x - (@prompt_size + next_line.size)
          move_real_cursor(x: -x, y: +1)
          move_abs_cursor(x: next_line.size, y: @y + 1)
        end
        true
      else
        false
      end
    end

    def move_cursor_to(x, y, allow_scrolling = true)
      if y > @y || (y == @y && x > @x)
        # Destination is after, move cursor forward:
        until {@x, @y} == {x, y}
          move_cursor_right(allow_scrolling: false)
          raise "Bug: position (#{x}, #{y}) missed when moving cursor forward" if @y > y
        end
      else
        # Destination is before, move cursor backward:
        until {@x, @y} == {x, y}
          move_cursor_left(allow_scrolling: false)
          raise "Bug: position (#{x}, #{y}) missed when moving cursor backward" if @y < y
        end
      end

      if allow_scrolling && update_scroll_offset
        update
      end
    end

    def move_cursor_to_begin(allow_scrolling = true)
      move_cursor_to(0, 0, allow_scrolling: allow_scrolling)
    end

    def move_cursor_to_end(allow_scrolling = true)
      y = @lines.size - 1

      move_cursor_to(@lines[y].size, y, allow_scrolling: allow_scrolling)
    end

    def move_cursor_to_end_of_line(y = @y, allow_scrolling = true)
      move_cursor_to(@lines[y].size, y, allow_scrolling: allow_scrolling)
    end

    # Refresh the screen.
    #
    # It clears the display of the current expression,
    # then yields for modifications, and displays the new expression.
    #
    # if *force_full_view* is true, whole expression is displayed, even if it overflow the term width, otherwise
    # the expression is bound and can be scrolled.
    def update(force_full_view = false, &)
      @output.print Term::Cursor.hide
      rewind_cursor
      header = update_header
      with self yield

      @expression = @expression_height = @colorized_lines = nil

      # Updated expression can be smaller so we might need to adjust the cursor:
      @y = @y.clamp(0, @lines.size - 1)
      @x = @x.clamp(0, @lines[@y].size)

      @output.print header
      print_expression(force_full_view)
      @output.print Term::Cursor.show
    end

    def update(force_full_view = false)
      @output.print Term::Cursor.hide
      rewind_cursor
      header = update_header

      @output.print header
      print_expression(force_full_view)
      @output.print Term::Cursor.show
    end

    # Clears previous headers (knowing its size), then call the header proc and returns it as string.
    private def update_header : String
      @output.print Term::Cursor.clear_line_after
      unless @header_height == 0
        @output.print Term::Cursor.up(@header_height)
        @output.print Term::Cursor.clear_screen_down
      end
      String.build do |io|
        @header_height = @header.call(io, @header_height)
      end
    end

    def replace(lines : Array(String))
      update { @lines = lines }
    end

    # Prints the full expression (without view bounds), and eventually replace it by *replacement*.
    def end_editing(replacement : Array(String)? = nil)
      if replacement
        update(force_full_view: true) do
          @lines = replacement
        end
      else
        update(force_full_view: true)
      end

      move_cursor_to_end(allow_scrolling: false)
      @output.puts
    end

    # Clears the expression and start a new prompt on a next line.
    def prompt_next
      @scroll_offset = 0
      @lines = [""]
      @expression = @expression_height = @colorized_lines = nil
      reset_cursor
      print_prompt(@output, 0)
    end

    private def print_prompt(io, line_index)
      io.print @prompt.call(line_index, color?)
      @prompt_size = @prompt.call(line_index, false).size # uncolorized size
    end

    def scroll_up
      if @scroll_offset < expression_height() - epression_max_height()
        @scroll_offset += 1
        update
      end
    end

    def scroll_down
      if @scroll_offset > 0
        @scroll_offset -= 1
        update
      end
    end

    private def scroll_up_if_needed
      if update_scroll_offset(y_shift: -1)
        update
      end
    end

    private def scroll_down_if_needed
      if update_scroll_offset(y_shift: +1)
        update
      end
    end

    # Updates the scroll offset in a way that (cursor + y_shift) is still between the view bounds
    # Returns true if the offset has been effectively modified.
    private def update_scroll_offset(y_shift = 0)
      start, end_ = view_bounds
      real_y = @lines.each.first(@y).sum { |l| line_height(l) }
      real_y += line_height(current_line[..@x]) - 1
      real_y += y_shift

      # case 1: cursor is before view start, we need to increase the scroll by the difference.
      if real_y < start
        @scroll_offset += start - real_y
        true

        # case 2: cursor is after view end, we need to decrease the scroll by the difference.
      elsif real_y > end_
        @scroll_offset -= real_y - end_
        true
      else
        false
      end
    end

    protected def expression_scrolled?
      expression_height() > epression_max_height()
    end

    # Returns y-start and end positions of the expression that should be displayed on the screen.
    # This take account of @scroll_offset, and the size start-end should never be greater than screen height.
    private def view_bounds
      end_ = expression_height() - 1

      start = {0, end_ + 1 - epression_max_height()}.max

      @scroll_offset = @scroll_offset.clamp(0, start) # @scroll_offset could not be greater than start.

      start -= @scroll_offset
      end_ -= @scroll_offset
      {start, end_}
    end

    # Rewinds the real cursor to the beginning of the expression without changing @x/@y cursor:
    private def rewind_cursor
      if expression_height >= self.height
        @output.print Term::Cursor.row(1)
      else
        x_save, y_save = @x, @y
        move_cursor_to_begin(allow_scrolling: false)
        @x, @y = x_save, y_save
      end

      @output.print Term::Cursor.column(1)
    end

    private def print_line(io, colorized_line, line_index, line_size, prompt?, first?, is_last_part?)
      if prompt?
        io.puts unless first?
        print_prompt(io, line_index)
      end
      io.print colorized_line

      # ```
      # prompt>begin                  |
      # prompt>  foooooooooooooooooooo|
      #                               | <- If the line size match exactly the screen width, we need to add a
      # prompt>  bar                  |    extra line feed, so computes based on `%` or `//` stay exact.
      # prompt>end                    |
      # ```
      io.puts if is_last_part? && last_part_size(line_size) == 0
    end

    # Prints the colorized expression, this later is clipped if it's higher than screen.
    # The only displayed part of the expression is delimited by `view_bounds` and depend of the value of
    # `@scroll_offset`.
    # Lines that takes more than one line (if wrapped) are cut in consequence.
    #
    # if *force_full_view* is true, all expression is dumped on screen, without clipping.
    private def print_expression(force_full_view = false)
      if force_full_view
        start, end_ = 0, Int32::MAX
      else
        update_scroll_offset()

        start, end_ = view_bounds()
      end

      first = true

      y = 0

      # While printing, real cursor move, but @x/@y don't, so we track the moved cursor position to be able to
      # restore real cursor at @x/@y position.
      cursor_move_x = cursor_move_y = 0

      display = String.build do |io|
        # Iterate over the uncolored lines because we need to know the true size of each line:
        @lines.each_with_index do |line, line_index|
          line_height = line_height(line)

          break if y > end_
          if y + line_height <= start
            y += line_height
            next
          end

          if start <= y && y + line_height - 1 <= end_
            # The line can hold entirely between the view bounds, print it:
            print_line(io, colorized_lines[line_index], line_index, line.size, prompt?: true, first?: first, is_last_part?: true)
            first = false

            cursor_move_x = line.size
            cursor_move_y = line_index

            y += line_height
          else
            # The line cannot holds entirely between the view bounds.
            # We need to cut the line into each part and display only parts that hold in the view
            colorized_parts = parts_from_colorized(colorized_lines[line_index])

            colorized_parts.each_with_index do |colorized_part, part_number|
              if start <= y <= end_
                # The part holds on the view, we can print it.
                print_line(io, colorized_part, line_index, line.size, prompt?: part_number == 0, first?: first, is_last_part?: part_number == line_height - 1)
                first = false

                cursor_move_x = {line.size, (part_number + 1)*self.width - @prompt_size - 1}.min
                cursor_move_y = line_index
              end
              y += 1
            end
          end
        end
      end

      @output.print Term::Cursor.clear_screen_down
      @output.print display

      # Retrieve the real cursor at its corresponding cursor position (`@x`, `@y`)
      x_save, y_save = @x, @y
      @y = cursor_move_y
      @x = cursor_move_x
      move_cursor_to(x_save, y_save, allow_scrolling: false)
    end

    # Splits the given *line* (colorized) into parts delimited by wrapping.
    #
    #  Because *line* is colorized, it's hard to know when it's wrap based on its size (colors sequence might appear anywhere in the string)
    #  Here we does the following:
    #  * Create a `String::Builder` for the first part (`part_builder`)
    #  * Iterate over the *line*, parsing the color sequence
    #  * Count cursor `x` for each char unless color sequences
    #  * If count goes over term width:
    #    reset `x` to 0, and create a new `String::Builder` for next part.
    private def parts_from_colorized(line)
      parts = Array(String).new

      color_sequence = ""
      part_builder = String::Builder.new

      x = @prompt_size
      chars = line.each_char
      until (c = chars.next).is_a? Iterator::Stop
        # Parse color sequence:
        if c == '\e' && chars.next == '['
          color_sequence = String.build do |seq|
            seq << '\e' << '['

            until (c = chars.next) == 'm'
              break if c.is_a? Iterator::Stop
              seq << c
            end
            seq << 'm'
          end
          part_builder << color_sequence
        else
          part_builder << c
          x += 1
        end

        if x >= self.width
          # Wrapping: save part and create a new builder for next part
          part_builder << "\e[0m"
          parts << part_builder.to_s
          part_builder = String::Builder.new
          part_builder << color_sequence # We also add the previous color sequence because color need to be preserved.
          x = 0
        end
      end
      parts << part_builder.to_s
      parts
    end
  end
end
