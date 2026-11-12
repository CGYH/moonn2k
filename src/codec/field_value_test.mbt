// FieldValue tests (plan 5.5: raw and physical both accessible, illegal
// enums never masquerade as known names).

///|
/// Physical values derive on demand while keeping the raw bits.
test "physical keeps raw and derives value" {
  let v : @codec.FieldValue = @codec.Physical(5010UL, 0.01, 0.0)
  assert_eq(v.raw(), Some(5010UL))
  let physical = v.physical()
  match physical {
    Some(x) => assert_true(x > 50.09 && x < 50.11)
    None => fail("physical value missing")
  }
}

///|
/// Illegal enum stays raw with no invented name.
test "lookup unknown enum keeps raw without name" {
  let known : @codec.FieldValue = @codec.Lookup(1UL, Some("North"))
  let unknown : @codec.FieldValue = @codec.Lookup(77UL, None)
  assert_eq(known.raw(), Some(1UL))
  assert_eq(unknown.raw(), Some(77UL))
  match unknown {
    @codec.Lookup(_, name) => assert_eq(name, None)
    _ => fail("not a lookup")
  }
}

///|
/// NotAvailable carries no raw value.
test "not available has no raw" {
  let v : @codec.FieldValue = @codec.NotAvailable
  assert_eq(v.raw(), None)
  assert_eq(v.physical(), None)
}
