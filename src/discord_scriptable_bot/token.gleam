import gleam/int
import gleam/time/calendar

pub type Token {
  // literals
  Name(String)
  String(String)
  Time(calendar.TimeOfDay)

  // keywords
  When
  User
  Any
  Post
  Message
  Containing
  And
  Or
  If
  Is
  Do
  Else
  Period
  Comma
  TimeKeyword

  // groupings
  LeftParen
  RightParen

  Space(String)
  EndOfFile

  UnexpectedGrapheme(String)
  UnterminatedString(String)
}

fn time_of_day_to_string(time: calendar.TimeOfDay) -> String {
  int.to_string(time.hours) <> int.to_string(time.minutes)
}

pub fn to_string(token: Token) -> String {
  case token {
    Name(value) -> "Name(" <> value <> ")"
    String(value) -> "String(" <> value <> ")"
    Time(value) -> "Time(" <> time_of_day_to_string(value) <> ")"

    When -> "When"
    User -> "User"
    Any -> "Any"
    Post -> "Post"
    Message -> "Message"
    Containing -> "Containing"
    And -> "And"
    Or -> "Or"
    If -> "If"
    Is -> "Is"
    Do -> "Do"
    Else -> "Else"
    Period -> "Period"
    Comma -> "Comma"
    TimeKeyword -> "TimeKeyword"

    LeftParen -> "LeftParen"
    RightParen -> "RightParen"

    Space(value) -> "Space(" <> value <> ")"
    EndOfFile -> "EndOfFile"

    UnexpectedGrapheme(value) -> "UnexpectedGrapheme(" <> value <> ")"
    UnterminatedString(value) -> "UnterminatedString(" <> value <> ")"
  }
}
