import discord_scriptable_bot/ast
import gleam/list
import gleam/option.{type Option, Some}
import gleam/time/calendar

pub type BotProgram {
  BotProgram(env: Environment, rules: List(Rule))
}

pub type Environment =
  List(#(String, Value))

pub type Value {
  StringValue(String)
  IntValue(Int)
}

pub type Rule {
  UserMessageRule(user: UserSelector, contains: Option(String), post: String)
  TimeRule(time: calendar.TimeOfDay, post: String)
}

pub type UserSelector {
  AnyUser
  Username(String)
}

pub type CompileError {
  UnknownVariable(name: String)
  ExpectedStringVariable(name: String)
  InvalidAssignment(
    assignment_type: ast.AssignmentType,
    value: ast.AssignmentValue,
  )
}

pub fn compile_program(program: ast.Program) -> Result(BotProgram, CompileError) {
  let ast.Program(statements) = program

  case compile_statements(statements, [], []) {
    Ok(#(env, rules)) -> Ok(BotProgram(env: env, rules: list.reverse(rules)))
    Error(error) -> Error(error)
  }
}

fn compile_statements(
  statements: List(ast.Statement),
  env: Environment,
  rules: List(Rule),
) -> Result(#(Environment, List(Rule)), CompileError) {
  case statements {
    [] -> Ok(#(env, rules))
    [statement, ..rest] ->
      case compile_statement(statement, env, rules) {
        Ok(#(next_env, next_rules)) ->
          compile_statements(rest, next_env, next_rules)
        Error(error) -> Error(error)
      }
  }
}

fn compile_statement(
  statement: ast.Statement,
  env: Environment,
  rules: List(Rule),
) -> Result(#(Environment, List(Rule)), CompileError) {
  case statement {
    ast.Assignment(assignment_type, id, value) ->
      case assignment_value_to_value(assignment_type, value) {
        Ok(runtime_value) -> Ok(#(put_env(env, id, runtime_value), rules))
        Error(error) -> Error(error)
      }

    ast.Expression(expression) ->
      case compile_expression(expression, env) {
        Ok(rule) -> Ok(#(env, [rule, ..rules]))
        Error(error) -> Error(error)
      }
  }
}

fn compile_expression(
  expression: ast.Expression,
  env: Environment,
) -> Result(Rule, CompileError) {
  case expression {
    ast.When(when_expr) -> compile_when(when_expr, env)
  }
}

fn compile_when(
  when_expr: ast.When,
  env: Environment,
) -> Result(Rule, CompileError) {
  case when_expr {
    ast.UserEvent(user, user_params, post) ->
      case compile_user_params(user_params, env) {
        Ok(contains) ->
          Ok(UserMessageRule(
            user: user_to_selector(user),
            contains: contains,
            post: post_message(post),
          ))
        Error(error) -> Error(error)
      }

    ast.TimeEvent(time, post) ->
      Ok(TimeRule(time: time, post: post_message(post)))
  }
}

fn compile_user_params(
  user_params: ast.UserParams,
  env: Environment,
) -> Result(Option(String), CompileError) {
  case user_params {
    ast.MessageLiteral(contents) -> Ok(contents)
    ast.MessageId(string_id) ->
      case lookup_string(env, string_id) {
        Ok(value) -> Ok(Some(value))
        Error(error) -> Error(error)
      }
  }
}

fn user_to_selector(user: ast.User) -> UserSelector {
  let ast.User(username) = user

  case username {
    "" -> AnyUser
    "any" -> AnyUser
    _ -> Username(username)
  }
}

fn post_message(post: ast.Post) -> String {
  let ast.Post(message) = post
  message
}

fn lookup_string(env: Environment, name: String) -> Result(String, CompileError) {
  case
    list.find(env, fn(curr_env) {
      let #(key, _value) = curr_env
      key == name
    })
  {
    Ok(#(_key, StringValue(value))) -> Ok(value)
    Ok(#(_key, _value)) -> Error(ExpectedStringVariable(name))
    Error(_) -> Error(UnknownVariable(name))
  }
}

fn assignment_value_to_value(
  assignment_type: ast.AssignmentType,
  value: ast.AssignmentValue,
) -> Result(Value, CompileError) {
  case assignment_type, value {
    ast.StringType, ast.StringValue(string_value) ->
      Ok(StringValue(string_value))
    ast.IntType, ast.IntValue(int_value) -> Ok(IntValue(int_value))
    _, _ -> Error(InvalidAssignment(assignment_type, value))
  }
}

fn put_env(env: Environment, name: String, value: Value) -> Environment {
  let filtered =
    list.filter(env, fn(curr_env) {
      let #(key, _value) = curr_env
      key != name
    })
  [#(name, value), ..filtered]
}
