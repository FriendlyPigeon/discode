import discord_scriptable_bot/ast
import discord_scriptable_bot/lexer.{type Lexer, type Position}
import discord_scriptable_bot/parser
import discord_scriptable_bot/token.{type Token}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
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

fn first_invalid_token(
  tokens: List(#(Token, Position)),
) -> Option(#(Token, Position)) {
  let found_token =
    list.find(tokens, fn(curr_token) {
      case curr_token {
        #(token.UnexpectedGrapheme(_), _pos) -> True
        #(token.UnterminatedString(_), _pos) -> True
        _ -> False
      }
    })
  case found_token {
    Ok(found_token) -> Some(found_token)
    Error(Nil) -> None
  }
}

// public parsing functions

pub fn parse_program(
  tokens: List(#(Token, Position)),
) -> Result(ast.Program, parser.ParserError) {
  case tokens {
    [] -> Error(parser.UnexpectedEndOfInput)
    all_tokens -> {
      case first_invalid_token(all_tokens) {
        Some(#(token.UnexpectedGrapheme(grapheme), pos)) -> {
          io.println_error(
            "Unexpected grapheme: "
            <> grapheme
            <> " at "
            <> pos.byte_offset |> int.to_string,
          )
          Error(parser.UnexpectedToken(token.UnexpectedGrapheme(grapheme), pos))
        }
        Some(#(token.UnterminatedString(str), pos)) -> {
          io.println_error(
            "Unterminated string: '"
            <> str
            <> "' at "
            <> pos.byte_offset |> int.to_string,
          )
          Error(parser.UnexpectedToken(token.UnterminatedString(str), pos))
        }
        Some(#(tok, pos)) -> {
          io.println_error(
            "Invalid token error: "
            <> token.to_string(tok)
            <> " at "
            <> pos.byte_offset |> int.to_string,
          )
          Error(parser.UnexpectedToken(tok, pos))
        }
        None -> {
          case parser.parse_statements(all_tokens, []) {
            Ok(statements) -> {
              Ok(ast.Program(statements))
            }
            Error(error) -> Error(error)
          }
        }
      }
    }
  }
}
