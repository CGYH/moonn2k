// Blackbox test for the root package public API.
// T00 gate: a clean clone must build and test green before protocol work.

///|
test {
  assert_eq(@moonn2k.hello(), "moonn2k")
}
