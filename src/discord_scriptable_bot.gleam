import discord_gleam
import discord_gleam/discord/intents
import discord_gleam/event_handler
import discord_gleam/types/user
import discord_gleam/ws/packets/message
import discord_scriptable_bot/ast
import discord_scriptable_bot/lexer
import discord_scriptable_bot/parser
import discord_scriptable_bot/runtime
import discord_scriptable_bot/token.{type Token}
import envoy
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/string
import gleam/time/calendar
import gleam/time/timestamp
import logging
import splitter

// public lexing functions

pub fn new(source: String) -> lexer.Lexer {
  lexer.Lexer(
    original_source: source,
    source:,
    byte_offset: 0,
    preserve_comments: True,
    preserve_whitespace: True,
    newlines: splitter.new(["\r\n", "\n", "\r"]),
  )
}

pub fn discard_whitespace(lexer: lexer.Lexer) -> lexer.Lexer {
  lexer.Lexer(..lexer, preserve_whitespace: False)
}

pub fn discard_comments(lexer: lexer.Lexer) -> lexer.Lexer {
  lexer.Lexer(..lexer, preserve_comments: False)
}

pub fn lex(lexer: lexer.Lexer) -> List(#(Token, lexer.Position)) {
  lexer.do_lex(lexer, [])
  |> list.reverse
}

fn first_invalid_token(
  tokens: List(#(Token, lexer.Position)),
) -> Option(#(Token, lexer.Position)) {
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
  tokens: List(#(Token, lexer.Position)),
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
      discord_gleam.new(bot, runtime_on_init, runtime_handler)
      |> discord_gleam.start()
    })

  let assert Ok(_) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(bot)
    |> supervisor.start()

  process.sleep_forever()
}

pub type LoadedSource {
  LoadedSource(channel_id: String, source: String)
}

pub type RuntimeState {
  RuntimeState(runtime: runtime.BotRuntime, sources: List(LoadedSource))
}

pub type LoadError {
  ParseError(parser.ParserError)
  CompileError(runtime.CompileError)
}

type Command {
  LoadProgram(source: String)
  ReloadPrograms
}

type RuntimeMessage {
  TimeTick
}

fn runtime_on_init(
  selector: process.Selector(RuntimeMessage),
) -> #(RuntimeState, process.Selector(RuntimeMessage)) {
  let tick_subject = process.new_subject()
  let selector = process.select(selector, tick_subject)
  let _ = process.spawn(fn() { time_loop(tick_subject) })
  let state = RuntimeState(runtime: runtime.empty_runtime(), sources: [])
  #(state, selector)
}

fn runtime_handler(
  bot,
  state: RuntimeState,
  msg: discord_gleam.HandlerMessage(RuntimeMessage),
) -> discord_gleam.Next(RuntimeState, RuntimeMessage) {
  case msg {
    discord_gleam.Packet(packet) ->
      case packet {
        event_handler.MessagePacket(message) ->
          handle_message(bot, state, message)
        _ -> discord_gleam.continue(state)
      }
    discord_gleam.User(TimeTick) -> handle_time_tick(bot, state)
  }
}

fn handle_message(
  bot,
  state: RuntimeState,
  message: message.MessagePacket,
) -> discord_gleam.Next(RuntimeState, RuntimeMessage) {
  let content = message.d.content

  case parse_command(content) {
    Some(command) -> handle_command(bot, state, message.d.channel_id, command)
    None ->
      handle_runtime_rules(
        bot,
        state,
        message.d.author,
        message.d.channel_id,
        content,
      )
  }
}

fn handle_runtime_rules(
  bot,
  state: RuntimeState,
  author: user.User,
  channel_id: String,
  content: String,
) -> discord_gleam.Next(RuntimeState, RuntimeMessage) {
  let RuntimeState(runtime: runtime_state, sources: _) = state

  let author_username = case author {
    user.PartialUser(username: username, ..) -> username
    user.FullUser(username: username, ..) -> username
  }

  runtime.match_message(runtime_state, author_username, content)
  |> list.each(fn(response) {
    let _ = discord_gleam.send_message(bot, channel_id, response, [])
    Nil
  })

  discord_gleam.continue(state)
}

fn handle_time_tick(
  bot,
  state: RuntimeState,
) -> discord_gleam.Next(RuntimeState, RuntimeMessage) {
  let RuntimeState(runtime: runtime_state, sources: _) = state
  let time = current_time_of_day()

  runtime.match_time(runtime_state, time)
  |> list.each(fn(time_post) {
    let runtime.TimePost(channel_id: channel_id, post: post) = time_post
    let _ = discord_gleam.send_message(bot, channel_id, post, [])
    Nil
  })

  discord_gleam.continue(state)
}

fn time_loop(subject: process.Subject(RuntimeMessage)) -> Nil {
  let delay = milliseconds_until_next_minute()
  process.sleep(delay)
  process.send(subject, TimeTick)
  time_loop(subject)
}

fn milliseconds_until_next_minute() -> Int {
  let now = timestamp.system_time()
  let #(_date, time) = timestamp.to_calendar(now, calendar.utc_offset)
  let calendar.TimeOfDay(
    hours: _,
    minutes: _,
    seconds: seconds,
    nanoseconds: nanoseconds,
  ) = time

  let assert Ok(nanoseconds_ms) = int.divide(nanoseconds, 1_000_000)
  let ms_into_minute = seconds * 1000 + nanoseconds_ms

  case ms_into_minute {
    0 -> 0
    _ -> 60_000 - ms_into_minute
  }
}

fn current_time_of_day() -> calendar.TimeOfDay {
  let now = timestamp.system_time()
  let #(_date, time) = timestamp.to_calendar(now, calendar.utc_offset)
  let calendar.TimeOfDay(
    hours: hours,
    minutes: minutes,
    seconds: _,
    nanoseconds: _,
  ) = time

  calendar.TimeOfDay(hours, minutes, 0, 0)
}

fn parse_command(content: String) -> Option(Command) {
  case content {
    "!reload" -> Some(ReloadPrograms)
    _ ->
      case string.starts_with(content, "!load ") {
        True -> Some(LoadProgram(string.drop_start(content, 6)))
        False -> None
      }
  }
}

fn handle_command(
  bot,
  state: RuntimeState,
  channel_id: String,
  command: Command,
) -> discord_gleam.Next(RuntimeState, RuntimeMessage) {
  case command {
    LoadProgram(source) ->
      case string.is_empty(source) {
        True -> {
          let _ =
            discord_gleam.send_message(
              bot,
              channel_id,
              "Usage: !load <script>",
              [],
            )
          discord_gleam.continue(state)
        }
        False ->
          case load_program(state, channel_id, source) {
            Ok(next_state) -> {
              let RuntimeState(runtime: _, sources: sources) = next_state
              let _ =
                discord_gleam.send_message(
                  bot,
                  channel_id,
                  "Loaded program. Total programs: "
                    <> int.to_string(list.length(sources)),
                  [],
                )
              discord_gleam.continue(next_state)
            }
            Error(error) -> {
              let _ =
                discord_gleam.send_message(
                  bot,
                  channel_id,
                  "Failed to load program: " <> load_error_to_string(error),
                  [],
                )
              discord_gleam.continue(state)
            }
          }
      }

    ReloadPrograms ->
      case reload_programs(state) {
        Ok(next_state) -> {
          let RuntimeState(runtime: _, sources: sources) = next_state
          let _ =
            discord_gleam.send_message(
              bot,
              channel_id,
              "Reloaded programs. Total programs: "
                <> int.to_string(list.length(sources)),
              [],
            )
          discord_gleam.continue(next_state)
        }
        Error(error) -> {
          let _ =
            discord_gleam.send_message(
              bot,
              channel_id,
              "Failed to reload programs: " <> load_error_to_string(error),
              [],
            )
          discord_gleam.continue(state)
        }
      }
  }
}

fn load_program(
  state: RuntimeState,
  channel_id: String,
  source: String,
) -> Result(RuntimeState, LoadError) {
  let RuntimeState(runtime: runtime_state, sources: sources) = state

  case compile_source(source) {
    Ok(program) ->
      Ok(RuntimeState(
        runtime: runtime.add_program_with_channel(
          runtime_state,
          program,
          channel_id,
        ),
        sources: list.append(sources, [LoadedSource(channel_id, source)]),
      ))
    Error(error) -> Error(error)
  }
}

fn reload_programs(state: RuntimeState) -> Result(RuntimeState, LoadError) {
  let RuntimeState(runtime: _, sources: sources) = state

  case compile_sources(sources) {
    Ok(programs) ->
      Ok(RuntimeState(
        runtime: runtime.runtime_from_programs_with_channels(programs),
        sources: sources,
      ))
    Error(error) -> Error(error)
  }
}

fn compile_sources(
  sources: List(LoadedSource),
) -> Result(List(runtime.ProgramWithChannel), LoadError) {
  case sources {
    [] -> Ok([])
    [LoadedSource(channel_id: channel_id, source: source), ..rest] ->
      case compile_source(source) {
        Ok(program) ->
          case compile_sources(rest) {
            Ok(programs) ->
              Ok([
                runtime.ProgramWithChannel(
                  program: program,
                  channel_id: channel_id,
                ),
                ..programs
              ])
            Error(error) -> Error(error)
          }
        Error(error) -> Error(error)
      }
  }
}

fn compile_source(source: String) -> Result(runtime.BotProgram, LoadError) {
  let tokens =
    source
    |> new()
    |> discard_whitespace()
    |> lex()

  case parse_program(tokens) {
    Ok(program) ->
      case runtime.compile_program(program) {
        Ok(bot_program) -> Ok(bot_program)
        Error(error) -> Error(CompileError(error))
      }
    Error(error) -> Error(ParseError(error))
  }
}

fn load_error_to_string(error: LoadError) -> String {
  case error {
    ParseError(parse_error) -> parser_error_to_string(parse_error)
    CompileError(compile_error) -> compile_error_to_string(compile_error)
  }
}

fn parser_error_to_string(error: parser.ParserError) -> String {
  case error {
    parser.UnexpectedEndOfInput -> "Unexpected end of input"
    parser.UnexpectedToken(tok, pos) -> {
      let lexer.Position(byte_offset: offset) = pos
      "Unexpected token "
      <> token.to_string(tok)
      <> " at "
      <> int.to_string(offset)
    }
  }
}

fn compile_error_to_string(error: runtime.CompileError) -> String {
  case error {
    runtime.UnknownVariable(name) -> "Unknown variable: " <> name
    runtime.ExpectedStringVariable(name) -> "Expected string variable: " <> name
    runtime.InvalidAssignment(assignment_type, value) ->
      "Invalid assignment: "
      <> assignment_type_to_string(assignment_type)
      <> " = "
      <> assignment_value_to_string(value)
  }
}

fn assignment_type_to_string(assignment_type: ast.AssignmentType) -> String {
  case assignment_type {
    ast.StringType -> "string"
    ast.IntType -> "int"
  }
}

fn assignment_value_to_string(value: ast.AssignmentValue) -> String {
  case value {
    ast.StringValue(string_value) -> "\"" <> string_value <> "\""
    ast.IntValue(int_value) -> int.to_string(int_value)
  }
}
