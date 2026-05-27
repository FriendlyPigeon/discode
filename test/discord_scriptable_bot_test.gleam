import discord_scriptable_bot
import discord_scriptable_bot/ast
import discord_scriptable_bot/lexer.{Position}
import discord_scriptable_bot/parser
import discord_scriptable_bot/runtime
import discord_scriptable_bot/token
import gleam/option.{None, Some}
import gleam/time/calendar
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn can_lex_basic_1_test() {
  "when user the_friendly_pigeon post message, post message \"hello world\"."
  |> discord_scriptable_bot.new()
  |> discord_scriptable_bot.discard_whitespace()
  |> discord_scriptable_bot.lex()
  |> should.equal([
    #(token.When, Position(0)),
    #(token.User, Position(5)),
    #(token.Name("the_friendly_pigeon"), Position(10)),
    #(token.Post, Position(30)),
    #(token.Message, Position(35)),
    #(token.Comma, Position(42)),
    #(token.Post, Position(44)),
    #(token.Message, Position(49)),
    #(token.String("hello world"), Position(57)),
    #(token.Period, Position(70)),
  ])
}

pub fn can_parse_basic_1_test() {
  [
    #(token.When, Position(0)),
    #(token.User, Position(5)),
    #(token.Name("the_friendly_pigeon"), Position(10)),
    #(token.Post, Position(30)),
    #(token.Message, Position(35)),
    #(token.Comma, Position(42)),
    #(token.Post, Position(44)),
    #(token.Message, Position(49)),
    #(token.String("hello world"), Position(57)),
    #(token.Period, Position(70)),
  ]
  |> discord_scriptable_bot.parse_program()
  |> should.equal(
    Ok(
      ast.Program([
        ast.Expression(
          ast.When(ast.UserEvent(
            ast.User("the_friendly_pigeon"),
            ast.MessageLiteral(None),
            ast.Post("hello world"),
          )),
        ),
      ]),
    ),
  )
}

pub fn can_compile_basic_1_test() {
  ast.Program([
    ast.Expression(
      ast.When(ast.UserEvent(
        ast.User("the_friendly_pigeon"),
        ast.MessageLiteral(None),
        ast.Post("hello world"),
      )),
    ),
  ])
  |> runtime.compile_program()
  |> should.equal(
    Ok(
      runtime.BotProgram(env: [], rules: [
        runtime.UserMessageRule(
          user: runtime.Username("the_friendly_pigeon"),
          contains: None,
          post: "hello world",
        ),
      ]),
    ),
  )
}

pub fn can_lex_unterminated_string_test() {
  "when user the_friendly_pigeon post message, post message \"hello world"
  |> discord_scriptable_bot.new()
  |> discord_scriptable_bot.discard_whitespace()
  |> discord_scriptable_bot.lex()
  |> should.equal([
    #(token.When, Position(0)),
    #(token.User, Position(5)),
    #(token.Name("the_friendly_pigeon"), Position(10)),
    #(token.Post, Position(30)),
    #(token.Message, Position(35)),
    #(token.Comma, Position(42)),
    #(token.Post, Position(44)),
    #(token.Message, Position(49)),
    #(token.UnterminatedString("hello world"), Position(57)),
  ])
}

pub fn can_parse_unterminated_string_test() {
  [
    #(token.When, Position(0)),
    #(token.User, Position(5)),
    #(token.Name("the_friendly_pigeon"), Position(10)),
    #(token.Post, Position(30)),
    #(token.Message, Position(35)),
    #(token.Comma, Position(42)),
    #(token.Post, Position(44)),
    #(token.Message, Position(49)),
    #(token.UnterminatedString("hello world"), Position(57)),
  ]
  |> discord_scriptable_bot.parse_program()
  |> should.equal(
    Error(parser.UnexpectedToken(
      token.UnterminatedString("hello world"),
      Position(57),
    )),
  )
}

pub fn can_compile_unterminated_string_test() {
  let parsed =
    [
      #(token.When, Position(0)),
      #(token.User, Position(5)),
      #(token.Name("the_friendly_pigeon"), Position(10)),
      #(token.Post, Position(30)),
      #(token.Message, Position(35)),
      #(token.Comma, Position(42)),
      #(token.Post, Position(44)),
      #(token.Message, Position(49)),
      #(token.UnterminatedString("hello world"), Position(57)),
    ]
    |> discord_scriptable_bot.parse_program()

  case parsed {
    Ok(program) ->
      program
      |> runtime.compile_program()
      |> should.equal(Error(runtime.UnknownVariable("__should_not_compile__")))
    Error(error) ->
      error
      |> should.equal(parser.UnexpectedToken(
        token.UnterminatedString("hello world"),
        Position(57),
      ))
  }
}

pub fn can_lex_string_variable_test() {
  "catch_phrase is \"a catch phrase\".\nwhen user any post message containing catch_phrase, post message \"that is your catch phrase\"."
  |> discord_scriptable_bot.new()
  |> discord_scriptable_bot.discard_whitespace()
  |> discord_scriptable_bot.lex()
  |> should.equal([
    #(token.Name("catch_phrase"), Position(0)),
    #(token.Is, Position(13)),
    #(token.String("a catch phrase"), Position(16)),
    #(token.Period, Position(32)),
    #(token.When, Position(34)),
    #(token.User, Position(39)),
    #(token.Any, Position(44)),
    #(token.Post, Position(48)),
    #(token.Message, Position(53)),
    #(token.Containing, Position(61)),
    #(token.Name("catch_phrase"), Position(72)),
    #(token.Comma, Position(84)),
    #(token.Post, Position(86)),
    #(token.Message, Position(91)),
    #(token.String("that is your catch phrase"), Position(99)),
    #(token.Period, Position(126)),
  ])
}

pub fn can_parse_string_variable_test() {
  [
    #(token.Name("catch_phrase"), Position(0)),
    #(token.Is, Position(13)),
    #(token.String("a catch phrase"), Position(16)),
    #(token.Period, Position(32)),
    #(token.When, Position(34)),
    #(token.User, Position(39)),
    #(token.Any, Position(44)),
    #(token.Post, Position(48)),
    #(token.Message, Position(53)),
    #(token.Containing, Position(61)),
    #(token.Name("catch_phrase"), Position(72)),
    #(token.Comma, Position(84)),
    #(token.Post, Position(86)),
    #(token.Message, Position(91)),
    #(token.String("that is your catch phrase"), Position(99)),
    #(token.Period, Position(126)),
  ]
  |> discord_scriptable_bot.parse_program()
  |> should.equal(
    Ok(
      ast.Program([
        ast.Assignment(
          ast.StringType,
          "catch_phrase",
          ast.StringValue("a catch phrase"),
        ),
        ast.Expression(
          ast.When(ast.UserEvent(
            ast.User(""),
            ast.MessageId("catch_phrase"),
            ast.Post("that is your catch phrase"),
          )),
        ),
      ]),
    ),
  )
}

pub fn can_compile_string_variable_test() {
  ast.Program([
    ast.Assignment(
      ast.StringType,
      "catch_phrase",
      ast.StringValue("a catch phrase"),
    ),
    ast.Expression(
      ast.When(ast.UserEvent(
        ast.User(""),
        ast.MessageId("catch_phrase"),
        ast.Post("that is your catch phrase"),
      )),
    ),
  ])
  |> runtime.compile_program()
  |> should.equal(
    Ok(
      runtime.BotProgram(
        env: [#("catch_phrase", runtime.StringValue("a catch phrase"))],
        rules: [
          runtime.UserMessageRule(
            user: runtime.AnyUser,
            contains: Some("a catch phrase"),
            post: "that is your catch phrase",
          ),
        ],
      ),
    ),
  )
}

pub fn can_lex_time_program_test() {
  "when time is 15:30, post message \"it is 3:30 PM UTC\"."
  |> discord_scriptable_bot.new()
  |> discord_scriptable_bot.discard_whitespace()
  |> discord_scriptable_bot.lex()
  |> should.equal([
    #(token.When, Position(0)),
    #(token.TimeKeyword, Position(5)),
    #(token.Is, Position(10)),
    #(token.Time(calendar.TimeOfDay(15, 30, 0, 0)), Position(13)),
    #(token.Comma, Position(18)),
    #(token.Post, Position(20)),
    #(token.Message, Position(25)),
    #(token.String("it is 3:30 PM UTC"), Position(33)),
    #(token.Period, Position(52)),
  ])
}

pub fn can_parse_time_program_test() {
  [
    #(token.When, Position(0)),
    #(token.TimeKeyword, Position(5)),
    #(token.Is, Position(10)),
    #(token.Time(calendar.TimeOfDay(15, 30, 0, 0)), Position(13)),
    #(token.Comma, Position(18)),
    #(token.Post, Position(20)),
    #(token.Message, Position(25)),
    #(token.String("it is 3:30 PM UTC"), Position(33)),
    #(token.Period, Position(52)),
  ]
  |> discord_scriptable_bot.parse_program()
  |> should.equal(
    Ok(
      ast.Program([
        ast.Expression(
          ast.When(ast.TimeEvent(
            time: calendar.TimeOfDay(15, 30, 0, 0),
            post: ast.Post("it is 3:30 PM UTC"),
          )),
        ),
      ]),
    ),
  )
}

pub fn can_compile_time_program_test() {
  ast.Program([
    ast.Expression(
      ast.When(ast.TimeEvent(
        time: calendar.TimeOfDay(15, 30, 0, 0),
        post: ast.Post("it is 3:30 PM UTC"),
      )),
    ),
  ])
  |> runtime.compile_program()
  |> should.equal(
    Ok(
      runtime.BotProgram(env: [], rules: [
        runtime.TimeRule(
          time: calendar.TimeOfDay(15, 30, 0, 0),
          post: "it is 3:30 PM UTC",
        ),
      ]),
    ),
  )
}
