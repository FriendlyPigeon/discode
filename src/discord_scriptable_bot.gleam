import discord_scriptable_bot/ast
import discord_scriptable_bot/lexer.{type Lexer, type Position}
import discord_scriptable_bot/parser
import discord_scriptable_bot/token.{type Token}
import gleam/list
import splitter

// public lexing functions

pub fn new(source: String) -> Lexer {
  lexer.Lexer(
    original_source: source,
    source:,
    byte_offset: 0,
    preserve_comments: True,
    preserve_whitespace: True,
    newlines: splitter.new(["\r\n", "\n", "\r"]),
  )
}

pub fn discard_whitespace(lexer: Lexer) -> Lexer {
  lexer.Lexer(..lexer, preserve_whitespace: False)
}

pub fn discard_comments(lexer: Lexer) -> Lexer {
  lexer.Lexer(..lexer, preserve_comments: False)
}

pub fn lex(lexer: Lexer) -> List(#(Token, Position)) {
  lexer.do_lex(lexer, [])
  |> list.reverse
}

// public parsing functions

pub fn parse_program(
  tokens: List(#(Token, Position)),
) -> Result(ast.Program, parser.ParserError) {
  case tokens {
    [] -> Error(parser.UnexpectedEndOfInput)
    all_tokens -> {
      case parser.parse_statements(all_tokens, []) {
        Ok(statements) -> {
          Ok(ast.Program(statements))
        }
        Error(error) -> Error(error)
      }
    }
  }
}
