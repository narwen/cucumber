module Cucumber
  module Ast
    # Holds the data of a table parsed from a feature file:
    #
    #   | a | b |
    #   | c | d |
    #
    # This gets parsed into a Table holding the values <tt>[['a', 'b'], ['c', 'd']]</tt>
    #
    class Table
      attr_accessor :file

      def initialize(raw)
        # Verify that it's square
        raw.transpose
        @raw = raw
        @cells_class = Cells
        @cell_class = Cell
        @conversion_procs = Hash.new(lambda{|cell_value| cell_value})
      end

      def at_lines?(lines)
        cells_rows.detect { |row| row.at_lines?(lines) }
      end

      def accept(visitor, status)
        cells_rows.each do |row|
          visitor.visit_table_row(row, status)
        end
        nil
      end

      # Converts this table into an Array of Hash where the keys of each
      # Hash are the headers in the table. For example, a Table built from
      # the following plain text:
      #
      #   | a | b | sum |
      #   | 2 | 3 | 5   |
      #   | 7 | 9 | 16  |
      #
      # Gets converted into the following:
      #
      #   [{'a' => '2', 'b' => '3', 'sum' => '5'}, {'a' => '7', 'b' => '9', 'sum' => '16'}]
      #
      # Use #map_column! to specify how values in a column are converted.
      #
      def hashes
        @hashes ||= cells_rows[1..-1].map do |row|
          row.to_hash
        end
      end

      # Gets the raw data of this table. For example, a Table built from
      # the following plain text:
      #
      #   | a | b |
      #   | c | d |
      #
      # Get converted into the following:
      #
      #   [['a', 'b], ['c', 'd']]
      #
      def raw
        @raw
      end

      # Same as #raw, but skips the first (header) row
      def rows
        @raw[1..-1]
      end

      def each_cells_row(&proc)
        cells_rows.each(&proc)
      end

      # For testing only
      def to_sexp #:nodoc:
        [:table, *cells_rows.map{|row| row.to_sexp}]
      end

      def map_headers(mappings)
        table = self.clone
        table.map_headers!(mappings)
        table
      end

      # Change how #hashes converts column values. The +column_name+ argument identifies the column
      # and +conversion_proc+ performs the conversion for each cell in that column. If +strict+ is 
      # true, an error will be raised if the column named +column_name+ is not found. If +strict+ 
      # is false, no error will be raised.
      def map_column!(column_name, strict=true, &conversion_proc)
        verify_column(column_name) if strict
        @conversion_procs[column_name] = conversion_proc
      end

      def to_hash(cells) #:nodoc:
        hash = Hash.new do |hash, key|
          hash[key.to_s] if key.is_a?(Symbol)
        end
        @raw[0].each_with_index do |column_name, column_index|
          value = @conversion_procs[column_name].call(cells.value(column_index))
          hash[column_name] = value
        end
        hash
      end

      def index(cells) #:nodoc:
        cells_rows.index(cells)
      end

      def verify_column(column_name)
        raise %{The column named "#{column_name}" does not exist} unless @raw[0].include?(column_name)
      end

      def arguments_replaced(arguments) #:nodoc:
        raw_with_replaced_args = raw.map do |row|
          row.map do |cell|
            cell_with_replaced_args = cell
            arguments.each do |name, value|
              cell_with_replaced_args = value ? cell_with_replaced_args.gsub(name, value) : nil
            end
            cell_with_replaced_args
          end
        end

        Table.new(raw_with_replaced_args)
      end

      def at_lines?(lines)
        cells_rows.detect{|row| row.at_lines?(lines)}
      end

      protected

      def map_headers!(mappings)
        headers = @raw[0]
        mappings.each_pair do |pre, post|
          headers[headers.index(pre)] = post
          if @conversion_procs.has_key?(pre)
            @conversion_procs[post] = @conversion_procs.delete(pre)
          end
        end
      end

      private

      def col_width(col)
        columns[col].__send__(:width)
      end

      def cells_rows
        @rows ||= cell_matrix.map do |cell_row|
          @cells_class.new(self, cell_row)
        end
      end

      def columns
        @columns ||= cell_matrix.transpose.map do |cell_row|
          @cells_class.new(self, cell_row)
        end
      end

      def cell_matrix
        row = -1
        @cell_matrix ||= @raw.map do |raw_row|
          line = raw_row.line rescue -1
          row += 1
          col = -1
          raw_row.map do |raw_cell|
            col += 1
            @cell_class.new(raw_cell, self, row, col, line)
          end
        end
      end

      # Represents a row of cells or columns of cells
      class Cells
        include Enumerable

        def initialize(table, cells)
          @table, @cells = table, cells
        end

        def accept(visitor, status)
          each do |cell|
            visitor.visit_table_cell(cell, status)
          end
          nil
        end

        # For testing only
        def to_sexp #:nodoc:
          [:row, *@cells.map{|cell| cell.to_sexp}]
        end

        def to_hash #:nodoc:
          @to_hash ||= @table.to_hash(self)
        end

        def value(n) #:nodoc:
          self[n].value
        end

        def [](n)
          @cells[n]
        end

        def line
          @cells[0].line
        end

        def at_lines?(lines)
          lines.empty? || lines.index(line)
        end

        private

        def index
          @table.index(self)
        end

        def width
          map{|cell| cell.value ? cell.value.to_s.jlength : 0}.max
        end

        def each(&proc)
          @cells.each(&proc)
        end
      end

      class Cell
        attr_reader :value, :line

        def initialize(value, table, row, col, line)
          @value, @table, @row, @col, @line = value, table, row, col, line
        end

        def accept(visitor, status)
          visitor.visit_table_cell_value(@value, col_width, status)
        end

        # For testing only
        def to_sexp #:nodoc:
          [:cell, @value]
        end

        private

        def col_width
          @col_width ||= @table.__send__(:col_width, @col)
        end
      end
    end
  end
end
