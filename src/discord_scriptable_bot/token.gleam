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
