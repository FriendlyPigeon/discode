import discord_scriptable_bot/ast
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import gleam/time/calendar

pub type BotProgram {
  BotProgram(env: Environment, rules: List(Rule))
}

pub type ProgramWithChannel {
  ProgramWithChannel(program: BotProgram, channel_id: String)
}

pub type TimeRuleWithChannel {
  TimeRuleWithChannel(
    time: calendar.TimeOfDay,
    post: String,
    channel_id: String,
  )
}

pub type TimePost {
  TimePost(channel_id: String, post: String)
}

pub type BotRuntime {
  BotRuntime(
    programs: List(BotProgram),
    rules: List(Rule),
    time_rules: List(TimeRuleWithChannel),
  )
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

pub fn empty_runtime() -> BotRuntime {
  BotRuntime(programs: [], rules: [], time_rules: [])
}

pub fn runtime_from_programs(programs: List(BotProgram)) -> BotRuntime {
  BotRuntime(
    programs: programs,
    rules: collect_user_rules(programs),
    time_rules: [],
  )
}

pub fn runtime_from_programs_with_channels(
  programs: List(ProgramWithChannel),
) -> BotRuntime {
  BotRuntime(
    programs: programs_from_with_channels(programs),
    rules: collect_user_rules_from_with_channels(programs),
    time_rules: collect_time_rules(programs),
  )
}

pub fn add_program(runtime: BotRuntime, program: BotProgram) -> BotRuntime {
  let BotRuntime(programs, rules, time_rules) = runtime
  let BotProgram(env: _, rules: program_rules) = program

  BotRuntime(
    programs: list.append(programs, [program]),
    rules: list.append(rules, user_rules_from_rules(program_rules)),
    time_rules: time_rules,
  )
}

pub fn add_program_with_channel(
  runtime: BotRuntime,
  program: BotProgram,
  channel_id: String,
) -> BotRuntime {
  let BotRuntime(programs, rules, time_rules) = runtime
  let BotProgram(env: _, rules: program_rules) = program

  BotRuntime(
    programs: list.append(programs, [program]),
    rules: list.append(rules, user_rules_from_rules(program_rules)),
    time_rules: list.append(
      time_rules,
      time_rules_from_rules(program_rules, channel_id),
    ),
  )
}

pub fn add_programs(
  runtime: BotRuntime,
  programs: List(BotProgram),
) -> BotRuntime {
  let BotRuntime(existing_programs, rules, time_rules) = runtime
  let new_rules = collect_user_rules(programs)

  BotRuntime(
    programs: list.append(existing_programs, programs),
    rules: list.append(rules, new_rules),
    time_rules: time_rules,
  )
}

pub fn add_programs_with_channels(
  runtime: BotRuntime,
  programs: List(ProgramWithChannel),
) -> BotRuntime {
  let BotRuntime(existing_programs, rules, time_rules) = runtime
  let new_programs = programs_from_with_channels(programs)

  BotRuntime(
    programs: list.append(existing_programs, new_programs),
    rules: list.append(rules, collect_user_rules_from_with_channels(programs)),
    time_rules: list.append(time_rules, collect_time_rules(programs)),
  )
}

pub fn match_message(
  runtime: BotRuntime,
  author_username: String,
  content: String,
) -> List(String) {
  let BotRuntime(programs: _, rules: rules, time_rules: _) = runtime

  list.fold(rules, [], fn(acc, rule) {
    case rule {
      UserMessageRule(user: user, contains: contains, post: post) ->
        case
          user_matches(user, author_username)
          && message_matches(contains, content)
        {
          True -> [post, ..acc]
          False -> acc
        }
      _ -> acc
    }
  })
  |> list.reverse
}

pub fn match_time(
  runtime: BotRuntime,
  time: calendar.TimeOfDay,
) -> List(TimePost) {
  let BotRuntime(programs: _, rules: _, time_rules: time_rules) = runtime

  list.fold(time_rules, [], fn(acc, rule) {
    let TimeRuleWithChannel(time: rule_time, post: post, channel_id: channel_id) =
      rule

    case rule_time == time {
      True -> [TimePost(channel_id: channel_id, post: post), ..acc]
      False -> acc
    }
  })
  |> list.reverse
}

fn collect_user_rules(programs: List(BotProgram)) -> List(Rule) {
  list.fold(programs, [], fn(acc, program) {
    let BotProgram(env: _, rules: program_rules) = program

    list.fold(program_rules, acc, fn(acc_inner, rule) {
      case rule {
        UserMessageRule(..) -> [rule, ..acc_inner]
        _ -> acc_inner
      }
    })
  })
  |> list.reverse
}

fn collect_user_rules_from_with_channels(
  programs: List(ProgramWithChannel),
) -> List(Rule) {
  list.fold(programs, [], fn(acc, program_with_channel) {
    let ProgramWithChannel(program: program, channel_id: _) =
      program_with_channel
    let BotProgram(env: _, rules: program_rules) = program

    list.fold(program_rules, acc, fn(acc_inner, rule) {
      case rule {
        UserMessageRule(..) -> [rule, ..acc_inner]
        _ -> acc_inner
      }
    })
  })
  |> list.reverse
}

fn collect_time_rules(
  programs: List(ProgramWithChannel),
) -> List(TimeRuleWithChannel) {
  list.fold(programs, [], fn(acc, program_with_channel) {
    let ProgramWithChannel(program: program, channel_id: channel_id) =
      program_with_channel
    let BotProgram(env: _, rules: program_rules) = program

    list.fold(program_rules, acc, fn(acc_inner, rule) {
      case rule {
        TimeRule(time: time, post: post) -> [
          TimeRuleWithChannel(time: time, post: post, channel_id: channel_id),
          ..acc_inner
        ]
        _ -> acc_inner
      }
    })
  })
  |> list.reverse
}

fn user_rules_from_rules(rules: List(Rule)) -> List(Rule) {
  list.fold(rules, [], fn(acc, rule) {
    case rule {
      UserMessageRule(..) -> [rule, ..acc]
      _ -> acc
    }
  })
  |> list.reverse
}

fn time_rules_from_rules(
  rules: List(Rule),
  channel_id: String,
) -> List(TimeRuleWithChannel) {
  list.fold(rules, [], fn(acc, rule) {
    case rule {
      TimeRule(time: time, post: post) -> [
        TimeRuleWithChannel(time: time, post: post, channel_id: channel_id),
        ..acc
      ]
      _ -> acc
    }
  })
  |> list.reverse
}

fn programs_from_with_channels(
  programs: List(ProgramWithChannel),
) -> List(BotProgram) {
  list.fold(programs, [], fn(acc, program_with_channel) {
    let ProgramWithChannel(program: program, channel_id: _) =
      program_with_channel
    [program, ..acc]
  })
  |> list.reverse
}

fn user_matches(selector: UserSelector, author_username: String) -> Bool {
  case selector {
    AnyUser -> True
    Username(name) -> name == author_username
  }
}

fn message_matches(contains: Option(String), content: String) -> Bool {
  case contains {
    None -> True
    Some(substring) -> string.contains(content, substring)
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
