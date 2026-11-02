unit memo.model;

// ---------------------------------------------------------------------------
//  qtxMemoisation - model
//
//  Each problem is written ONCE as an "open recursive" function: instead of
//  calling itself by name it calls the Recurse function it is handed. That
//  lets the same definition run two ways:
//
//    Naive     Recurse is the function itself - every sub-problem is
//              solved again each time it appears (exponential).
//    Memoised  Recurse looks in a cache first - every sub-problem is solved
//              once (linear or polynomial).
//
//  The cache is a TPersistentMap from the qtxFunctional package, so even
//  memoisation stays functional: each Put returns a new map version.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.lazy,
  functional.lazylist,
  functional.sequence,
  functional.collections;

const
  NaiveCallBudget = 3000000;
  MaxTreeLines    = 250;

type
  TProblemKind = (pkFibonacci, pkStairs, pkGrid);

  TSelfCall      = function (Key: Variant): Variant;
  TOpenRecursive = function (const Recurse: TSelfCall; Key: Variant): Variant;

  TTextLines = array of String;

  TRecursionStats = class
  private
    FLines: TTextLines;
  public
    Answer:   Variant;
    Calls:    Integer;
    Hits:     Integer;
    Entries:  Integer;
    MaxDepth: Integer;
    Aborted:  Boolean;
    TimeMs:   Float;

    // The call tree is drawn top-down: a call reserves its line when it
    // starts and fills in its result when it finishes
    function  Open: Integer;
    procedure Close(Index, Depth: Integer; const Text: String);
    function  TreeText: String;
  end;

  TMemoModel = class
  public
    class function ProblemTitle(Kind: TProblemKind): String;
    class function ProblemNote(Kind: TProblemKind): String;
    class function MaxN(Kind: TProblemKind): Integer;
    class function Definition(Kind: TProblemKind): TOpenRecursive;
    class function StartKey(Kind: TProblemKind; N: Integer): Variant;
    class function KeyText(Kind: TProblemKind; Key: Variant): String;

    class function RunNaive(Kind: TProblemKind; N: Integer): TRecursionStats;
    class function RunMemoised(Kind: TProblemKind; N: Integer): TRecursionStats;

    // A deliberately slow computation for the TLazyValue section
    class function CountPrimes(Limit: Integer): Integer;

    // A fresh self-referential Fibonacci list (memoised lazy tails)
    class function FibonacciList: TLazyList;
  end;

function NumText(const Value: Variant): String;

implementation

function NumText(const Value: Variant): String;
begin
  Result := FloatToStr(TVariant.AsFloat(Value));
end;

function Number(const Value: Variant): Float;
begin
  Result := TVariant.AsFloat(Value);
end;

{ TRecursionStats }

function TRecursionStats.Open: Integer;
begin
  if Length(FLines) >= MaxTreeLines then
    exit(-1);
  FLines.Add('');
  Result := High(FLines);
end;

procedure TRecursionStats.Close(Index, Depth: Integer; const Text: String);
var
  Indent: String;
  i: Integer;
begin
  if Index < 0 then
    exit;
  Indent := '';
  for i := 1 to Depth do
    Indent := Indent + '|   ';
  FLines[Index] := Indent + Text;
end;

function TRecursionStats.TreeText: String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to High(FLines) do
    Result := Result + FLines[i] + #10;
  if Calls > Length(FLines) then
    Result := Result + '... ' + IntToStr(Calls - Length(FLines)) +
      ' more calls not shown' + #10;
end;

{ Problems }

class function TMemoModel.ProblemTitle(Kind: TProblemKind): String;
begin
  case Kind of
    pkFibonacci: Result := 'Fibonacci: fib(n) = fib(n-1) + fib(n-2)';
    pkStairs:    Result := 'Staircase: ways to climb n steps, 1, 2 or 3 at a time';
    pkGrid:      Result := 'Grid paths: routes across an n x n grid, moving right or down';
  end;
end;

class function TMemoModel.ProblemNote(Kind: TProblemKind): String;
begin
  case Kind of
    pkFibonacci: Result := 'fib(0) = 0 and fib(1) = 1. Naively, fib(n-2) is solved again inside fib(n-1), and so on all the way down.';
    pkStairs:    Result := 'ways(0) = 1, ways(negative) = 0, ways(n) = ways(n-1) + ways(n-2) + ways(n-3). Three branches per call make the naive version grow even faster.';
    pkGrid:      Result := 'paths(r, 0) = paths(0, c) = 1 and paths(r, c) = paths(r-1, c) + paths(r, c-1). The answer is the binomial coefficient C(2n, n).';
  end;
end;

class function TMemoModel.MaxN(Kind: TProblemKind): Integer;
begin
  case Kind of
    pkFibonacci: Result := 75;   // fib(75) is still exact in a double
    pkStairs:    Result := 60;
    pkGrid:      Result := 25;
  end;
end;

class function TMemoModel.StartKey(Kind: TProblemKind; N: Integer): Variant;
begin
  if Kind = pkGrid then
    Result := N * 100 + N      // key encodes (row, column)
  else
    Result := N;
end;

class function TMemoModel.KeyText(Kind: TProblemKind; Key: Variant): String;
var
  K: Integer;
begin
  K := Key;
  case Kind of
    pkFibonacci: Result := 'fib(' + IntToStr(K) + ')';
    pkStairs:    Result := 'ways(' + IntToStr(K) + ')';
    pkGrid:      Result := 'paths(' + IntToStr(K div 100) + ',' + IntToStr(K mod 100) + ')';
  end;
end;

class function TMemoModel.Definition(Kind: TProblemKind): TOpenRecursive;
begin
  case Kind of
    pkFibonacci:
      Result := function (const Recurse: TSelfCall; Key: Variant): Variant
        var
          N: Integer;
        begin
          N := Key;
          if N < 2 then
            Result := N
          else
            Result := Number(Recurse(N - 1)) + Number(Recurse(N - 2));
        end;

    pkStairs:
      Result := function (const Recurse: TSelfCall; Key: Variant): Variant
        var
          N: Integer;
        begin
          N := Key;
          if N = 0 then
            Result := 1
          else if N < 0 then
            Result := 0
          else
            Result := Number(Recurse(N - 1)) + Number(Recurse(N - 2)) + Number(Recurse(N - 3));
        end;

  else
    // pkGrid: Key = row * 100 + column
    Result := function (const Recurse: TSelfCall; Key: Variant): Variant
      var
        K: Integer;
      begin
        K := Key;
        if ((K div 100) = 0) or ((K mod 100) = 0) then
          Result := 1
        else
          Result := Number(Recurse(K - 100)) + Number(Recurse(K - 1));
      end;
  end;
end;

{ Running }

class function TMemoModel.RunNaive(Kind: TProblemKind; N: Integer): TRecursionStats;
var
  Stats: TRecursionStats;
  F: TOpenRecursive;
  Recurse: TSelfCall;
  Depth: Integer;
  Started: Float;
  Problem: TProblemKind;
begin
  Stats := TRecursionStats.Create;
  F := Definition(Kind);
  Problem := Kind;
  Depth := 0;

  // Recurse calls the definition directly: nothing is remembered
  Recurse := function (Key: Variant): Variant
    var
      K, Line, MyDepth: Integer;
    begin
      Inc(Stats.Calls);
      if Stats.Calls > NaiveCallBudget then
        raise EFunctional.Create('budget');
      K := Key;
      MyDepth := Depth;
      if MyDepth > Stats.MaxDepth then
        Stats.MaxDepth := MyDepth;
      Line := Stats.Open;
      Inc(Depth);
      Result := F(Recurse, Key);
      Dec(Depth);
      Stats.Close(Line, MyDepth, TMemoModel.KeyText(Problem, K) + ' = ' + NumText(Result));
    end;

  Started := Now;
  try
    Stats.Answer := Recurse(StartKey(Kind, N));
  except
    on E: EFunctional do
      Stats.Aborted := True;
  end;
  Stats.TimeMs := (Now - Started) * 86400000;
  Result := Stats;
end;

class function TMemoModel.RunMemoised(Kind: TProblemKind; N: Integer): TRecursionStats;
var
  Stats: TRecursionStats;
  F: TOpenRecursive;
  Recurse: TSelfCall;
  Cache: TPersistentMap;
  Depth: Integer;
  Started: Float;
  Problem: TProblemKind;
begin
  Stats := TRecursionStats.Create;
  F := Definition(Kind);
  Problem := Kind;
  Cache := TPersistentMap.Empty;
  Depth := 0;

  // Recurse consults the cache first; each new answer produces a new map
  Recurse := function (Key: Variant): Variant
    var
      Name: String;
      K, Line, MyDepth: Integer;
    begin
      Inc(Stats.Calls);
      K := Key;
      Name := IntToStr(K);
      MyDepth := Depth;
      if MyDepth > Stats.MaxDepth then
        Stats.MaxDepth := MyDepth;
      Line := Stats.Open;
      if Cache.ContainsKey(Name) then
      begin
        Inc(Stats.Hits);
        Result := Cache.Get(Name);
        Stats.Close(Line, MyDepth, TMemoModel.KeyText(Problem, K) + ' = ' +
          NumText(Result) + '      <- from the cache');
        exit;
      end;
      Inc(Depth);
      Result := F(Recurse, Key);
      Dec(Depth);
      Cache := Cache.Put(Name, Result);
      Stats.Close(Line, MyDepth, TMemoModel.KeyText(Problem, K) + ' = ' + NumText(Result));
    end;

  Started := Now;
  Stats.Answer := Recurse(StartKey(Kind, N));
  Stats.TimeMs := (Now - Started) * 86400000;
  Stats.Entries := Cache.Count;
  Result := Stats;
end;

class function TMemoModel.CountPrimes(Limit: Integer): Integer;
begin
  // Written as a pipeline; trial division keeps it deliberately slow
  Result := TSequence.Range(2, Limit)
    .Filter(function (Value: Variant): Boolean
      var
        N, d: Integer;
      begin
        N := Value;
        d := 2;
        while d * d <= N do
        begin
          if (N mod d) = 0 then
            exit(False);
          Inc(d);
        end;
        Result := True;
      end)
    .Count;
end;

class function TMemoModel.FibonacciList: TLazyList;
var
  Fibs: TLazyList;
begin
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
  Result := Fibs;
end;

end.
