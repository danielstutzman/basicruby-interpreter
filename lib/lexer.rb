class Lexer
  def build_start_pos_to_end_pos code
    start_pos_to_end_pos = {}

    lexer = Opal::Lexer.new code, '(eval)'
    parser = Opal::Parser.new
    parser.instance_variable_set :@lexer, lexer
    parser.instance_variable_set :@file, '(eval)'
    parser.instance_variable_set :@scopes, []
    parser.push_scope :block
    lexer.parser = parser

    while true
      token_symbol, value = parser.next_token

      if token_symbol == false
        break
      elsif token_symbol == :tINTEGER ||
         token_symbol == :tFLOAT
        excerpt = lexer.scanner.matched
      else
        excerpt = value[0]
      end
      start_pos = value[1]
      end_pos = value[1].clone
      end_pos[1] += excerpt.length
      start_pos_to_end_pos[start_pos] = end_pos
    end
    start_pos_to_end_pos
  end
  def build_line_start_pos_to_end_pos code
    line_start_pos_to_end_pos = {}

    lexer = Opal::Lexer.new code, '(eval)'
    parser = Opal::Parser.new
    parser.instance_variable_set :@lexer, lexer
    parser.instance_variable_set :@file, '(eval)'
    parser.instance_variable_set :@scopes, []
    parser.push_scope :block
    lexer.parser = parser

    last_start_pos = nil
    last_end_pos = nil
    directly_after_do = false
    while true
      token_symbol, value = parser.next_token

      if token_symbol == false
        if last_start_pos && last_end_pos
          line_start_pos_to_end_pos[last_start_pos] = last_end_pos
          last_start_pos = nil
          last_end_pos = nil
        end
        break
      elsif token_symbol == :kDO || token_symbol == :tLCURLY
        if last_start_pos && last_end_pos
          line_start_pos_to_end_pos[last_start_pos] = last_end_pos
          last_start_pos = nil
          last_end_pos = nil
        end
        directly_after_do = true
        next
      elsif directly_after_do && token_symbol == :tPIPE
        parser.next_token
        parser.next_token
        next
        directly_after_do = false
      elsif token_symbol == :tINTEGER ||
         token_symbol == :tFLOAT
        excerpt = lexer.scanner.matched
      elsif token_symbol == :tNL || token_symbol == :tSEMI
        if last_start_pos && last_end_pos
          line_start_pos_to_end_pos[last_start_pos] = last_end_pos
          last_start_pos = nil
          last_end_pos = nil
        end
        next
      else
        excerpt = value[0]
      end
      directly_after_do = false
      last_start_pos = value[1] if last_start_pos.nil?
      end_pos = value[1].clone
      end_pos[1] += excerpt.length
      last_end_pos = end_pos
    end
    line_start_pos_to_end_pos
  end
end

if __FILE__ == $0
  send :require, 'opal'
  p Lexer.new.build_start_pos_to_end_pos("puts 3\nputs 4")
  p Lexer.new.build_line_start_pos_to_end_pos("[1, 2].each do |x|
  p x
  p x
end")
  p Lexer.new.build_line_start_pos_to_end_pos("{} & a.map { |x| x * 2 }")
end
