unit tests.extensions;

// ---------------------------------------------------------------------------
//  qtxFunctional - tests for Scan, FlatMap, ZipWith / ZipWithList and the
//  AVL-balanced TPersistentMap. Expected values were computed independently
//  (Python reference implementations).
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.lazylist,
  functional.sequence,
  functional.collections,
  tests.roadmap;

procedure RunExtensionTests(const Check: TCheckProc; const Section: TSectionProc);

implementation

function VarText(const Value: Variant): String;
begin
  Result := Value;
end;

function Key(N: Integer): String;
begin
  Result := IntToStr(N);
  while Length(Result) < 4 do
    Result := '0' + Result;
  Result := 'k' + Result;
end;

function Below(Limit: Integer): TVarPredicate;
var
  Bound: Integer;
begin
  Bound := Limit;
  Result := function (Value: Variant): Boolean
    var
      N: Integer;
    begin
      N := Value;
      Result := N < Bound;
    end;
end;

function Joined: TVarFoldFunc;
begin
  Result := function (A, B: Variant): Variant
    begin
      Result := VarText(A) + VarText(B);
    end;
end;

{ Scan }

procedure TestScan(const Check: TCheckProc; const Section: TSectionProc);
var
  Sums, Fused: TSequence;
begin
  Section('Extensions - Scan (running accumulation)');
  Sums := TSequence.Range(1, 5).Scan(0, TVarFunction.LiftFold(TFunction.Sum()));
  Check('Range(1,5).Scan(0, +)', Sums.AsString, '[1, 3, 6, 10, 15]');
  Check('  ...re-run starts from the seed again', Sums.AsString, '[1, 3, 6, 10, 15]');
  Check('Running maximum',
    TSequence.FromArray([3, 1, 4, 1, 5, 9, 2, 6])
      .Scan(0, TVarFunction.LiftFold(TFunction.Maximum())).AsString,
    '[3, 3, 4, 4, 5, 9, 9, 9]');
  Check('Triangular numbers below 100 (infinite source)',
    TSequence.From(1).Scan(0, TVarFunction.LiftFold(TFunction.Sum()))
      .TakeWhile(Below(100)).AsString,
    '[1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 66, 78, 91]');

  Fused := TSequence.Range(1, 4)
    .Map(TVarFunction.Lift(TFunction.Square()))
    .Scan(0, TVarFunction.LiftFold(TFunction.Sum()));
  Check('Map then Scan fuse into one stage', Fused.Describe, 'Range(1..4) -> Scan{x2}');
  Check('  ...running sum of squares', Fused.AsString, '[1, 5, 14, 30]');
end;

{ FlatMap }

procedure TestFlatMap(const Check: TCheckProc; const Section: TSectionProc);
var
  Pulled: Integer;
  Spy: TVarFunc;
  Triples: TSequence;
begin
  Section('Extensions - FlatMap');
  Check('Range(1,3).FlatMap(n -> Replicate(n, n))',
    TSequence.Range(1, 3).FlatMap(
      function (Value: Variant): TSequence
      var
        N: Integer;
      begin
        N := Value;
        Result := TSequence.Replicate(N, N);
      end).AsString,
    '[1, 2, 2, 3, 3, 3]');

  Pulled := 0;
  Spy := function (Value: Variant): Variant
    begin
      Inc(Pulled);
      Result := Value;
    end;
  Check('From(1).FlatMap(n -> Range(1,n)).Take(7)',
    TSequence.From(1).Map(Spy).FlatMap(
      function (Value: Variant): TSequence
      var
        N: Integer;
      begin
        N := Value;
        Result := TSequence.Range(1, N);
      end).Take(7).AsString,
    '[1, 1, 2, 1, 2, 3, 1]');
  Check('  ...outer elements pulled from the infinite source', IntToStr(Pulled), '4');

  // Nested FlatMaps: every inner pipeline closes over c and b
  Triples := TSequence.From(1).FlatMap(
    function (CValue: Variant): TSequence
    var
      C: Integer;
    begin
      C := CValue;
      Result := TSequence.Range(1, C).FlatMap(
        function (BValue: Variant): TSequence
        var
          B: Integer;
        begin
          B := BValue;
          Result := TSequence.Range(1, B)
            .Filter(function (AValue: Variant): Boolean
              var
                A: Integer;
              begin
                A := AValue;
                Result := A * A + B * B = C * C;
              end)
            .Map(function (AValue: Variant): Variant
              begin
                Result := '(' + VarText(AValue) + ',' + IntToStr(B) + ',' + IntToStr(C) + ')';
              end);
        end);
    end).Take(4);
  Check('First 4 Pythagorean triples (nested FlatMap)', Triples.AsString,
    '[(3,4,5), (6,8,10), (5,12,13), (9,12,15)]');

  try
    TSequence.Range(1, 2).FlatMap(
      function (Value: Variant): TSequence
      begin
        Result := TSequence.From(1);
      end).Count;
    Check('Unbounded inner sequence rejected', 'no error', 'EFunctional');
  except
    on E: EFunctional do
      Check('Unbounded inner sequence rejected', 'EFunctional', 'EFunctional');
  end;
end;

{ Zip }

procedure TestZip(const Check: TCheckProc; const Section: TSectionProc);
var
  Fibs: TLazyList;
  Bounded: TSequence;
begin
  Section('Extensions - ZipWith and ZipWithList');
  Check('Range(1,5).ZipWith(Array[a,b,c], join)',
    TSequence.Range(1, 5).ZipWith(TSequence.FromArray(['a', 'b', 'c']), Joined()).AsString,
    '[1a, 2b, 3c]');

  Bounded := TSequence.From(1).ZipWith(TSequence.Range(10, 12),
    TVarFunction.LiftFold(TFunction.Product()));
  Check('Infinite.ZipWith(bounded) is itself bounded', BoolToStr(Bounded.IsBounded), BoolToStr(True));
  Check('From(1).ZipWith(Range(10,12), *) - no Take needed', Bounded.AsString, '[10, 22, 36]');

  Fibs := TLazyList.Cons(0,
    function: TLazyList
    begin
      Result := TLazyList.Cons(1,
        function: TLazyList
        begin
          Result := TLazyList.ZipWith(Fibs, Fibs.Tail,
            TVarFunction.LiftFold(TFunction.Sum()));
        end);
    end);
  Check('From(0).ZipWithList(infinite Fibs).Take(6)',
    TSequence.From(0).ZipWithList(Fibs,
      function (N, F: Variant): Variant
      begin
        Result := 'F' + VarText(N) + '=' + VarText(F);
      end).Take(6).AsString,
    '[F0=0, F1=1, F2=1, F3=2, F4=3, F5=5]');
  Check('Range(1,3).ZipWithList(finite list)',
    TSequence.Range(1, 3).ZipWithList(TLazyList.FromArray(['x', 'y']), Joined()).AsString,
    '[1x, 2y]');

  try
    TSequence.Range(1, 3).ZipWith(TSequence.From(1), Joined());
    Check('ZipWith rejects an unbounded partner', 'no error', 'EFunctional');
  except
    on E: EFunctional do
      Check('ZipWith rejects an unbounded partner', 'EFunctional', 'EFunctional');
  end;
end;

{ AVL-balanced persistent map }

procedure TestBalancedMap(const Check: TCheckProc; const Section: TSectionProc);
var
  Full, Half: TPersistentMap;
  Keys: TStrArray;
  i: Integer;
  Sorted: Boolean;
begin
  Section('Extensions - AVL-balanced TPersistentMap');
  Full := TPersistentMap.Empty;
  for i := 1 to 1000 do
    Full := Full.Put(Key(i), i);
  Check('1000 keys inserted in sorted order: count', IntToStr(Full.Count), '1000');
  Check('  ...height (unbalanced BST would be 1000)', IntToStr(Full.Height), '10');
  Check('  ...AVL and ordering invariants hold', BoolToStr(Full.IsBalanced), BoolToStr(True));

  Half := Full;
  for i := 1 to 1000 do
    if (i mod 2) = 1 then
      Half := Half.Remove(Key(i));
  Check('After removing the 500 odd keys: count', IntToStr(Half.Count), '500');
  Check('  ...height', IntToStr(Half.Height), '9');
  Check('  ...invariants still hold', BoolToStr(Half.IsBalanced), BoolToStr(True));

  Keys := Half.Keys;
  Sorted := True;
  for i := 1 to High(Keys) do
    if Keys[i - 1] >= Keys[i] then
      Sorted := False;
  Check('  ...keys remain in order', BoolToStr(Sorted), BoolToStr(True));
  Check('  ...first and last keys', Keys[0] + ' .. ' + Keys[High(Keys)], 'k0002 .. k1000');

  Check('Old version still has k0001', VarText(Full.Get(Key(1))), '1');
  Check('New version does not', BoolToStr(Half.ContainsKey(Key(1))), BoolToStr(False));
  Check('Old version still balanced after 500 derived removals',
    BoolToStr(Full.IsBalanced and (Full.Count = 1000)), BoolToStr(True));
end;

procedure RunExtensionTests(const Check: TCheckProc; const Section: TSectionProc);
begin
  TestScan(Check, Section);
  TestFlatMap(Check, Section);
  TestZip(Check, Section);
  TestBalancedMap(Check, Section);
end;

end.
