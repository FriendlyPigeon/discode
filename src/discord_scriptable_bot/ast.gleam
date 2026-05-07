import gleam/option.{type Option}
import gleam/time/calendar

pub type Program {
  Program(body: List(Statement))
}

pub type Statement {
  Assignment(
    assignment_type: AssignmentType,
    id: String,
    value: AssignmentValue,
  )
  Expression(Expression)
}

pub type AssignmentType {
  StringType
  IntType
}

pub type AssignmentValue {
  StringValue(String)
  IntValue(Int)
}

pub type Expression {
  When(When)
}

pub type Post {
  Post(message: String)
}

pub type When {
  UserEvent(user: User, user_params: UserParams, post: Post)
  TimeEvent(time: calendar.TimeOfDay, post: Post)
}

pub type User {
  User(username: String)
}

pub type UserParams {
  Message(contents: Option(String))
}

pub type Entity
