require './bytecode_interpreter.rb'
require './bytecode_spool.rb'
require 'opal'

class RspecRubyRunner
  def initialize
    parser = Opal::Parser.new
    sexp1 = parser.parse BytecodeInterpreter.RUNTIME_PRELUDE
    compiler = AstToBytecodeCompiler.new
    @bytecodes1 = compiler.compile_program 'Runtime', sexp1
  end
  def output_from ruby_code
    parser = Opal::Parser.new
    compiler = AstToBytecodeCompiler.new
    sexp2 = parser.parse ruby_code
    bytecodes2 = compiler.compile_program 'TestCode', sexp2
    spool = BytecodeSpool.new @bytecodes1 + [[:discard]] + bytecodes2
    interpreter = BytecodeInterpreter.new

    spool.queue_run_until 'DONE'
    begin
      while true
        bytecode = spool.get_next_bytecode
        break if bytecode.nil?

        spool_command = interpreter.interpret bytecode
        spool.do_command *spool_command if spool_command
      end
      interpreter.visible_state[:output].map { |pair| pair[1] }.join
    rescue ProgramTerminated => e
      interpreter.undefine_methods!
      raise e.cause
    end
  end
end
