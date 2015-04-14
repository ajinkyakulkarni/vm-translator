class CodeWriter
  def initialize(output)
    @output  = output
    @counter = 0
  end

  def set_file_name(filename)
  end

  def close
    output.close
  end

  def write_arithmetic(command)
    case command
    when 'add', 'sub', 'and', 'or'
      output.puts <<-EOF
        @SP
        // SP--
        MD=M-1
        // Load M[SP]
        A=M
        D=M
        // Load M[SP-1]
        A=A-1
        // Add M[SP] to M[SP-1]
        M=M#{operand(command)}D
      EOF
    when 'neg', 'not'
      output.puts <<-EOF
        @SP
        A=M-1
        M=#{operand(command)}M
      EOF
    when 'eq', 'gt', 'lt'
      true_label, end_label = 2.times.map { generate_label }
      output.puts <<-EOF
        @SP
        // SP--
        MD=M-1
        // Load M[SP]
        A=M
        D=M
        // Load M[SP-1]
        A=A-1
        // Subtract M[SP-1] from M[SP]
        D=M-D
        // If the result satisfies command then jump to (TRUE)
        @#{true_label}
        D;J#{command.upcase}
        // Load M[SP]
        @SP
        A=M-1
        // M[SP-1] = 0
        M=0
        // Jump to (END)
        @#{end_label}
        0;JMP
        (#{true_label})
        // Load M[SP]
        @SP
        A=M-1
        // M[SP-1] = -1
        M=-1
        (#{end_label})
      EOF
    end
  end

  def write_push_pop(command, segment, index)
    case command
    when Parser::C_PUSH
      write_push(segment, index)
    when Parser::C_POP
      load_base_address_into_r13(segment, index)
      pop_stack_into_d
      output.puts <<-EOF
        @R13
        A=M
        M=D
      EOF
    end
  end

  def write_label(label)
    output.puts "($#{label})"
  end

  def write_goto(label)
    output.puts <<-EOF
      @$#{label}
      0;JMP
    EOF
  end

  def write_if(label)
    pop_stack_into_d
    output.puts <<-EOF
      // Jump to the label's address if D is nonzero
      @$#{label}
      D;JNE
    EOF
  end

  def write_function(function_name, num_locals)
    output.puts "(#{function_name})"
    num_locals.times do
      write_push 'constant', 0
    end
  end

  private

  attr_reader :output

  def write_push(segment, index)
    case segment
    when 'constant'
      output.puts <<-EOF
        // Load index into M[SP]
        @#{index}
        D=A
      EOF
    else
      load_base_address_into_r13(segment, index)
      output.puts <<-EOF
        @R13
        A=M
        D=M
      EOF
    end

    output.puts <<-EOF
      // RAM[SP]=D
      @SP
      A=M
      M=D
      // SP++
      @SP
      M=M+1
    EOF
  end

  def load_base_address_into_r13(segment, offset)
    load_destination_into_d(segment, offset)

    output.puts <<-EOF
      // Store the destination in R13
      @R13        // A=13
      M=D         // RAM[13]=302
    EOF
  end

  def pop_stack_into_d
    output.puts <<-EOF
      @SP
      AM=M-1
      D=M
    EOF
  end

  def load_destination_into_d(segment, offset)
    output.puts "@#{symbol_for_segment(segment, offset)}"

    if symbol_known_at_compile_time?(segment)
      output.puts "D=A"
    else
      output.puts "D=M"
      apply_offset_at_runtime(offset)
    end
  end

  def symbol_for_segment(segment, offset)
    case segment
    when 'temp'
      5 + offset
    when 'pointer'
      3 + offset
    when 'static'
      "STATIC.#{offset}"
    else
      base_address(segment)
    end
  end

  def symbol_known_at_compile_time?(segment)
    %w(temp pointer static).include? segment
  end

  def apply_offset_at_runtime(offset)
    return if offset.zero?

    output.puts <<-EOF
      // Add the index offset to the base address
      @#{offset}
      D=A+D
    EOF
  end

  def operand(command)
    {
      'add' => '+',
      'sub' => '-',
      'and' => '&',
      'or'  => '|',
      'neg' => '-',
      'not' => '!'
    }.fetch(command)
  end

  def base_address(segment)
    {
      'local'    => 'LCL',
      'argument' => 'ARG',
      'this'     => 'THIS',
      'that'     => 'THAT'
    }.fetch(segment)
  end

  def generate_label
    @counter += 1
    "LABEL#{@counter}"
  end
end
