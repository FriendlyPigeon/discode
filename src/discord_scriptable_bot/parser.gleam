import discord_scriptable_bot.{type Position}
import discord_scriptable_bot/ast
import discord_scriptable_bot/token.{type Token}
import gleam/list
import gleam/option.{None, Some}

pub type ParserError {
  UnexpectedEndOfInput
  UnexpectedToken(token: Token, position: Position)
}

pub fn parse_program(
  tokens: List(#(Token, Position)),
) -> Result(ast.Program, ParserError) {
  case tokens {
    [] -> Error(UnexpectedEndOfInput)
    all_tokens -> {
      case parse_statements(all_tokens, []) {
        Ok(statements) -> {
          Ok(ast.Program(statements))
        }
        Error(error) -> Error(error)
      }
    }
  }
}

// fn syntax_error(error: String, error_type: Error) -> ParserError {
//   io.print_error(error)
//   error_type
// }

fn parse_statements(
  tokens: List(#(Token, Position)),
  statements: List(ast.Statement),
) -> Result(List(ast.Statement), ParserError) {
  case list.length(statements), statements {
    0, [] -> Error(UnexpectedEndOfInput)
    0, all_statements -> Ok(all_statements)
    _token_count, all_statements -> {
      case parse_statement(tokens) {
        Ok(statement) -> {
          parse_statements(
            list.drop(tokens, 4),
            list.append(all_statements, [statement]),
          )
        }
        Error(error) -> Error(error)
      }
    }
  }
}

fn parse_statement(
  tokens: List(#(Token, Position)),
) -> Result(ast.Statement, ParserError) {
  case tokens {
    [#(token.Name(_name), _pos), ..] ->
      case parse_assignment(tokens) {
        Ok(assignment) -> Ok(assignment)
        Error(error) -> Error(error)
      }
    [#(token.When, _pos), ..] ->
      case parse_when(tokens) {
        Ok(when) -> Ok(ast.Expression(ast.When(when)))
        Error(error) -> Error(error)
      }
    [#(unexpected_token, pos), ..] ->
      Error(UnexpectedToken(unexpected_token, pos))
    [] -> Error(UnexpectedEndOfInput)
  }
}

fn parse_assignment(
  tokens: List(#(Token, Position)),
) -> Result(ast.Statement, ParserError) {
  case tokens {
    [
      #(token.Name(named_id), _pos),
      #(token.Is, _pos),
      #(token.String(string_value), _pos),
      #(token.Period, _pos),
      ..
    ] ->
      Ok(ast.Assignment(ast.StringType, named_id, ast.StringValue(string_value)))
    [
      #(token.Name(_named_id), _pos),
      #(unexpected_token, pos),
      #(token.String(_string_value), _pos),
      #(token.Period, _pos),
      ..
    ] -> Error(UnexpectedToken(unexpected_token, pos))
    [
      #(token.Name(_named_id), _pos),
      #(token.Is, _pos),
      #(unexpected_token, pos),
      #(token.Period, _pos),
      ..
    ] -> Error(UnexpectedToken(unexpected_token, pos))
    _ -> Error(UnexpectedEndOfInput)
  }
}

fn parse_when(tokens: List(#(Token, Position))) -> Result(ast.When, ParserError) {
  case tokens {
    [#(token.When, _pos), #(token.User, _pos), ..] ->
      parse_when_user(list.drop(tokens, 2))
    [#(token.When, _pos), #(token.TimeKeyword, _pos), ..] ->
      parse_when_time(list.drop(tokens, 2))
    _ -> Error(UnexpectedEndOfInput)
  }
}

fn parse_when_user(
  tokens: List(#(Token, Position)),
) -> Result(ast.When, ParserError) {
  case tokens {
    [
      #(token.Name(username), _pos),
      #(token.Post, _pos),
      #(token.Message, _pos),
      #(token.Containing, _pos),
      #(token.String(matched_message), _pos),
      #(token.Comma, _pos),
      #(token.Post, _pos),
      #(token.Message, _pos),
      #(token.String(message), _pos),
      #(token.Period, _pos),
      ..
    ] ->
      Ok(ast.UserEvent(
        ast.User(username),
        ast.Message(Some(matched_message)),
        ast.Post(message),
      ))
    [
      #(token.Name(username), _pos),
      #(token.Post, _pos),
      #(token.Message, _pos),
      #(token.Comma, _pos),
      #(token.Post, _pos),
      #(token.Message, _pos),
      #(token.String(message), _pos),
      #(token.Period, _pos),
      ..
    ] ->
      Ok(ast.UserEvent(ast.User(username), ast.Message(None), ast.Post(message)))
    _ -> Error(UnexpectedEndOfInput)
  }
}

fn parse_when_time(
  tokens: List(#(Token, Position)),
) -> Result(ast.When, ParserError) {
  case tokens {
    [
      #(token.Is, _pos),
      #(token.Time(time_of_day), _pos),
      #(token.Comma, _pos),
      #(token.Post, _pos),
      #(token.Message, _pos),
      #(token.String(message), _pos),
      #(token.Period, _pos),
      ..
    ] -> Ok(ast.TimeEvent(time_of_day, ast.Post(message)))
    _ -> Error(UnexpectedEndOfInput)
  }
}
