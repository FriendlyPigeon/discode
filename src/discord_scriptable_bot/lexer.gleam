import discord_scriptable_bot/token.{type Token}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar
import splitter

pub type Lexer {
  Lexer(
    original_source: String,
    source: String,
    byte_offset: Int,
    preserve_whitespace: Bool,
    preserve_comments: Bool,
    newlines: splitter.Splitter,
  )
}

pub type Position {
  Position(byte_offset: Int)
}

pub fn do_lex(lexer: Lexer, tokens: List(#(Token, Position))) {
  case next(lexer) {
    #(lexer, None) -> do_lex(lexer, tokens)
    #(_lexer, Some(#(token.EndOfFile, _))) -> tokens
    #(lexer, Some(token)) -> do_lex(lexer, [token, ..tokens])
  }
}

fn next(lexer: Lexer) -> #(Lexer, Option(#(Token, Position))) {
  case lexer.source {
    // whitespace
    " " <> source | "\n" <> source | "\r" <> source | "\t" <> source ->
      advance(lexer, source, 1)
      |> whitespace(lexer.byte_offset, 1)

    // groupings
    "(" <> source -> token(lexer, token.LeftParen, source, 1)
    ")" <> source -> token(lexer, token.RightParen, source, 1)

    "." <> source -> token(lexer, token.Period, source, 1)
    "," <> source -> token(lexer, token.Comma, source, 1)

    "\"" <> source -> {
      advance(lexer, source, 1)
      |> lex_string(lexer.byte_offset, 0)
    }

    // keywords and literals
    "a" <> source
    | "b" <> source
    | "c" <> source
    | "d" <> source
    | "e" <> source
    | "f" <> source
    | "g" <> source
    | "h" <> source
    | "i" <> source
    | "j" <> source
    | "k" <> source
    | "l" <> source
    | "m" <> source
    | "n" <> source
    | "o" <> source
    | "p" <> source
    | "q" <> source
    | "r" <> source
    | "s" <> source
    | "t" <> source
    | "u" <> source
    | "v" <> source
    | "w" <> source
    | "x" <> source
    | "y" <> source
    | "z" <> source -> {
      let byte_offset = lexer.byte_offset
      let #(lexer, name) =
        advance(lexer, source, 1)
        |> lex_lowercase_name(byte_offset, 1)

      let token = case name {
        "when" -> token.When
        "any" -> token.Any
        "post" -> token.Post
        "message" -> token.Message
        "containing" -> token.Containing
        "and" -> token.And
        "or" -> token.Or
        "if" -> token.If
        "is" -> token.Is
        "do" -> token.Do
        "else" -> token.Else
        "user" -> token.User
        "time" -> token.TimeKeyword
        _name -> token.Name(name)
      }

      #(lexer, Some(#(token, Position(byte_offset:))))
    }

    "0" <> source
    | "1" <> source
    | "2" <> source
    | "3" <> source
    | "4" <> source
    | "5" <> source
    | "6" <> source
    | "7" <> source
    | "8" <> source
    | "9" <> source -> {
      let byte_offset = lexer.byte_offset
      let #(lexer, time) =
        advance(lexer, source, 1)
        |> lex_time(byte_offset)

      #(lexer, time)
    }

    _ -> {
      case string.pop_grapheme(lexer.source) {
        Error(_) -> #(
          lexer,
          Some(#(token.EndOfFile, Position(lexer.byte_offset))),
        )

        Ok(#(grapheme, source)) -> {
          token(
            lexer,
            token.UnexpectedGrapheme(grapheme),
            source,
            string.length(grapheme),
          )
        }
      }
    }
  }
}

fn lex_time(lexer: Lexer, start: Int) -> #(Lexer, Option(#(Token, Position))) {
  let potential_time = string.slice(lexer.original_source, start, 5)
  case string_to_time_of_day(potential_time) {
    Ok(time) -> {
      let new_lexer = advance(lexer, string.drop_start(lexer.source, 4), 4)
      #(new_lexer, Some(#(token.Time(time), Position(lexer.byte_offset - 1))))
    }
    Error(Nil) -> {
      #(
        lexer,
        Some(#(token.UnexpectedGrapheme("nil"), Position(lexer.byte_offset - 1))),
      )
    }
  }
}

fn string_to_time_of_day(
  potential_time: String,
) -> Result(calendar.TimeOfDay, Nil) {
  case
    parse_hours(string.slice(potential_time, 0, 2)),
    parse_minutes(string.slice(potential_time, 3, 2))
  {
    Ok(hours), Ok(minutes) -> {
      Ok(calendar.TimeOfDay(hours, minutes, 0, 0))
    }
    _, _ -> Error(Nil)
  }
}

fn parse_hours(hours: String) -> Result(Int, Nil) {
  case int.parse(hours) {
    Ok(hours) if hours >= 0 && hours <= 23 -> Ok(hours)
    Ok(_hours) -> Error(Nil)
    Error(_) -> Error(Nil)
  }
}

fn parse_minutes(minutes: String) -> Result(Int, Nil) {
  case int.parse(minutes) {
    Ok(minutes) if minutes >= 0 && minutes <= 59 -> Ok(minutes)
    Ok(_minutes) -> Error(Nil)
    Error(_) -> Error(Nil)
  }
}

fn lex_string(
  lexer: Lexer,
  start: Int,
  slice_size: Int,
) -> #(Lexer, Option(#(Token, Position))) {
  case lexer.source {
    "\"" <> source -> {
      let content = string.slice(lexer.original_source, start + 1, slice_size)
      #(token.String(content), Position(byte_offset: start))
      |> advanced(lexer, source, 1)
      |> some_token
    }

    "\\" <> source ->
      case string.pop_grapheme(source) {
        Error(_) ->
          advance(lexer, source, 1)
          |> lex_string(start, slice_size + 1)

        Ok(#(grapheme, source)) -> {
          let offset = 1 + string.length(grapheme)
          advance(lexer, source, offset)
          |> lex_string(start, slice_size + offset)
        }
      }

    "" -> {
      let content = string.slice(lexer.original_source, start + 1, slice_size)
      #(
        lexer,
        Some(#(token.UnterminatedString(content), Position(byte_offset: start))),
      )
    }

    _ ->
      advance(lexer, string.drop_start(lexer.source, 1), 1)
      |> lex_string(start, slice_size + 1)
  }
}

fn lex_lowercase_name(
  lexer: Lexer,
  start: Int,
  slice_size: Int,
) -> #(Lexer, String) {
  case lexer.source {
    "a" <> source
    | "b" <> source
    | "c" <> source
    | "d" <> source
    | "e" <> source
    | "f" <> source
    | "g" <> source
    | "h" <> source
    | "i" <> source
    | "j" <> source
    | "k" <> source
    | "l" <> source
    | "m" <> source
    | "n" <> source
    | "o" <> source
    | "p" <> source
    | "q" <> source
    | "r" <> source
    | "s" <> source
    | "t" <> source
    | "u" <> source
    | "v" <> source
    | "w" <> source
    | "x" <> source
    | "y" <> source
    | "z" <> source
    | "0" <> source
    | "1" <> source
    | "2" <> source
    | "3" <> source
    | "4" <> source
    | "5" <> source
    | "6" <> source
    | "7" <> source
    | "8" <> source
    | "9" <> source
    | "_" <> source ->
      advance(lexer, source, 1)
      |> lex_lowercase_name(start, slice_size + 1)
    _ -> {
      let name = string.slice(lexer.original_source, start, slice_size)
      #(lexer, name)
    }
  }
}

fn whitespace(
  lexer: Lexer,
  start: Int,
  slice_size: Int,
) -> #(Lexer, Option(#(Token, Position))) {
  case lexer.source {
    " " <> source | "\t" <> source | "\n" <> source | "\r" <> source ->
      advance(lexer, source, 1)
      |> whitespace(start, slice_size + 1)

    _ ->
      case lexer.preserve_whitespace {
        False -> #(lexer, None)
        True -> {
          let content = string.slice(lexer.original_source, start, slice_size)
          #(lexer, Some(#(token.Space(content), Position(byte_offset: start))))
        }
      }
  }
}

fn advance(lexer: Lexer, source: String, offset: Int) -> Lexer {
  Lexer(..lexer, source:, byte_offset: lexer.byte_offset + offset)
}

fn advanced(
  token: #(Token, Position),
  lexer: Lexer,
  source: String,
  offset: Int,
) -> #(Lexer, #(Token, Position)) {
  #(advance(lexer, source, offset), token)
}

fn some_token(
  result: #(Lexer, #(Token, Position)),
) -> #(Lexer, Option(#(Token, Position))) {
  let #(lexer, token) = result
  #(lexer, Some(token))
}

fn token(
  lexer: Lexer,
  token: Token,
  source: String,
  offset: Int,
) -> #(Lexer, Option(#(Token, Position))) {
  #(token, Position(byte_offset: lexer.byte_offset))
  |> advanced(lexer, source, offset)
  |> some_token
}
