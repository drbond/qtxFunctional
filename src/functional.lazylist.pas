unit functional.lazylist;

// ---------------------------------------------------------------------------
//  qtxFunctional - TLazyList
//
//  A lazy linked list in the Haskell style: a strict head and a *lazy,
//  memoised* tail. Because the tail is only built when first demanded, and
//  then cached, lists can be defined recursively - even in terms of
//  themselves:
//
//      Ones := Cons(1, -> Ones)                         // 1, 1, 1, ...
//      Fibs := Cons(0, -> Cons(1, -> ZipWith(Fibs, Fibs.Tail, +)))
//
//  Memoisation is what makes the self-referential Fibs efficient: each cell
//  is computed once, so the n-th element costs O(n) instead of O(2^n).
//
//  Nodes are immutable. Operations return new lists that share structure.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions;

type
  TLazyList = class;

  TLazyListThunk = function: TLazyList;

  TLazyList = class
  private
    FHead:        Variant;
    FEmpty:       Boolean;
    FTailThunk:   TLazyListThunk;
    FTail:        TLazyList;
    FTailForced:  Boolean;
    class var FEmptyList: TLazyList;
    class function Link(const Head: Variant; const Tail: TLazyList): TLazyList;
    function GetHead: Variant;
    function GetTail: TLazyList;
  public
    // Number of tail thunks actually executed - shows memoisation at work
    class var ForcedTails: Integer;

    constructor Create(const Head: Variant; const Tail: TLazyListThunk; IsEmpty: Boolean);

    class function Empty: TLazyList;
    class function Cons(const Head: Variant; const Tail: TLazyListThunk): TLazyList;
    class function Iterate(const Seed: Variant; const Next: TVarFunc): TLazyList;
    class function ZipWith(const A, B: TLazyList; const Fn: TVarFoldFunc): TLazyList;
    class function FromArray(const Values: TVarArray): TLazyList;

    function Map(const Fn: TVarFunc): TLazyList;
    function Filter(const Predicate: TVarPredicate): TLazyList;  // needs a match to exist
    function Take(Count: Integer): TLazyList;
    function Drop(Count: Integer): TLazyList;
    function Nth(Index: Integer): Variant;

    // Finite lists only - Take first on an infinite list
    function Fold(const Seed: Variant; const Fn: TVarFoldFunc): Variant;
    function ToArray: TVarArray;
    function AsString: String;

    property Head: Variant read GetHead;
    property Tail: TLazyList read GetTail;
    property IsEmpty: Boolean read FEmpty;
  end;

implementation

constructor TLazyList.Create(const Head: Variant; const Tail: TLazyListThunk;
  IsEmpty: Boolean);
begin
  FHead := Head;
  FTailThunk := Tail;
  FEmpty := IsEmpty;
  FTailForced := False;
end;

class function TLazyList.Empty: TLazyList;
begin
  if FEmptyList = nil then
    FEmptyList := TLazyList.Create(0, nil, True);
  Result := FEmptyList;
end;

class function TLazyList.Cons(const Head: Variant; const Tail: TLazyListThunk): TLazyList;
begin
  Result := TLazyList.Create(Head, Tail, False);
end;

function TLazyList.GetHead: Variant;
begin
  if FEmpty then
    raise EFunctional.Create('TLazyList.Head: list is empty');
  Result := FHead;
end;

function TLazyList.GetTail: TLazyList;
begin
  if FEmpty then
    raise EFunctional.Create('TLazyList.Tail: list is empty');
  if not FTailForced then
  begin
    Inc(ForcedTails);
    if Assigned(FTailThunk) then
      FTail := FTailThunk()
    else
      FTail := TLazyList.Empty;
    FTailForced := True;
    FTailThunk := nil;   // memoised - release the closure
  end;
  Result := FTail;
end;

class function TLazyList.Iterate(const Seed: Variant; const Next: TVarFunc): TLazyList;
var
  Current: Variant;
  Step: TVarFunc;
begin
  Current := Seed;
  Step := Next;
  Result := TLazyList.Cons(Current,
    function: TLazyList
    begin
      Result := TLazyList.Iterate(Step(Current), Step);
    end);
end;

class function TLazyList.ZipWith(const A, B: TLazyList; const Fn: TVarFoldFunc): TLazyList;
var
  Left, Right: TLazyList;
  Combine: TVarFoldFunc;
begin
  if A.IsEmpty or B.IsEmpty then
    exit(TLazyList.Empty);
  Left := A;
  Right := B;
  Combine := Fn;
  Result := TLazyList.Cons(Combine(Left.Head, Right.Head),
    function: TLazyList
    begin
      Result := TLazyList.ZipWith(Left.Tail, Right.Tail, Combine);
    end);
end;

class function TLazyList.Link(const Head: Variant; const Tail: TLazyList): TLazyList;
begin
  // A cell whose tail is already known (no thunk needed)
  Result := TLazyList.Create(Head, nil, False);
  Result.FTail := Tail;
  Result.FTailForced := True;
end;

class function TLazyList.FromArray(const Values: TVarArray): TLazyList;
var
  i: Integer;
  Built: TLazyList;
begin
  // Build back to front so each cell's tail is already known
  Built := TLazyList.Empty;
  for i := High(Values) downto 0 do
    Built := Link(Values[i], Built);
  Result := Built;
end;

function TLazyList.Map(const Fn: TVarFunc): TLazyList;
var
  Source: TLazyList;
  Mapper: TVarFunc;
begin
  if FEmpty then
    exit(Self);
  Source := Self;
  Mapper := Fn;
  Result := TLazyList.Cons(Mapper(FHead),
    function: TLazyList
    begin
      Result := Source.Tail.Map(Mapper);
    end);
end;

function TLazyList.Filter(const Predicate: TVarPredicate): TLazyList;
var
  Cursor: TLazyList;
  Test: TVarPredicate;
begin
  Test := Predicate;
  Cursor := Self;
  while (not Cursor.IsEmpty) and (not Test(Cursor.Head)) do
    Cursor := Cursor.Tail;
  if Cursor.IsEmpty then
    exit(Cursor);
  Result := TLazyList.Cons(Cursor.Head,
    function: TLazyList
    begin
      Result := Cursor.Tail.Filter(Test);
    end);
end;

function TLazyList.Take(Count: Integer): TLazyList;
var
  Source: TLazyList;
  Remaining: Integer;
begin
  if FEmpty or (Count <= 0) then
    exit(TLazyList.Empty);
  Source := Self;
  Remaining := Count - 1;
  Result := TLazyList.Cons(FHead,
    function: TLazyList
    begin
      if Remaining <= 0 then
        Result := TLazyList.Empty
      else
        Result := Source.Tail.Take(Remaining);
    end);
end;

function TLazyList.Drop(Count: Integer): TLazyList;
var
  i: Integer;
begin
  Result := Self;
  for i := 1 to Count do
  begin
    if Result.IsEmpty then
      break;
    Result := Result.Tail;
  end;
end;

function TLazyList.Nth(Index: Integer): Variant;
begin
  Result := Drop(Index).Head;
end;

function TLazyList.Fold(const Seed: Variant; const Fn: TVarFoldFunc): Variant;
var
  Cursor: TLazyList;
begin
  Result := Seed;
  Cursor := Self;
  while not Cursor.IsEmpty do
  begin
    Result := Fn(Result, Cursor.Head);
    Cursor := Cursor.Tail;
  end;
end;

function TLazyList.ToArray: TVarArray;
var
  Cursor: TLazyList;
begin
  Cursor := Self;
  while not Cursor.IsEmpty do
  begin
    Result.Add(Cursor.Head);
    Cursor := Cursor.Tail;
  end;
end;

function TLazyList.AsString: String;
var
  Items: TVarArray;
  Text: String;
  i: Integer;
begin
  Items := ToArray;
  Result := '[';
  for i := 0 to High(Items) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Text := Items[i];
    Result := Result + Text;
  end;
  Result := Result + ']';
end;

end.
