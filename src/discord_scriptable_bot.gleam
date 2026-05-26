import discord_gleam
import discord_gleam/discord/intents
import discord_gleam/event_handler
import discord_scriptable_bot/ast
import discord_scriptable_bot/lexer.{type Lexer, type Position}
import discord_scriptable_bot/parser
import discord_scriptable_bot/token.{type Token}
import envoy
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import logging
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

// discord bot

pub fn main() {
  logging.configure()
  logging.set_level(logging.Debug)

  let discord_client_id = case envoy.get("DISCORD_CLIENT_ID") {
    Ok(id) -> id
    Error(Nil) ->
      panic as "The environment variable DISCORD_CLIENT_ID must be set"
  }

  let discord_token = case envoy.get("DISCORD_TOKEN") {
    Ok(token) -> token
    Error(Nil) -> panic as "The environment variable DISCORD_TOKEN must be set"
  }

  let bot =
    discord_gleam.bot(discord_token, discord_client_id, intents.default())

  let bot =
    supervision.worker(fn() {
      discord_gleam.simple(bot, [simple_handler])
      |> discord_gleam.start()
    })

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(bot)
    |> supervisor.start()

  process.sleep_forever()
}

fn simple_handler(bot, packet: event_handler.Packet) {
  case packet {
    event_handler.MessagePacket(message) -> {
      logging.log(logging.Info, "Got message: " <> message.d.content)

      case message.d.content {
        "!ping" -> {
          discord_gleam.send_message(bot, message.d.channel_id, "Pong!", [])

          Nil
        }

        _ -> Nil
      }
    }

    _ -> Nil
  }
}
