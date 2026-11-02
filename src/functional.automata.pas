unit functional.automata;

// ---------------------------------------------------------------------------
//  qtxFunctional - elementary cellular automata  (Stage 6)
//
//  A generation is an immutable String of '0' and '1' cells (wrap-around
//  edges). A rule number (0..255, Wolfram's numbering) becomes a pure
//  function  generation -> next generation.
//
//  Because the step is a pure function, the entire history of an automaton
//  is just  TSequence.Iterate(Initial, Rule(N))  - an infinite, lazy
//  sequence of generations that is only computed as far as it is read.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.sequence;

type
  TAutomaton = class
  public
    class function NextGeneration(const Generation: String; RuleNumber: Integer): String;
    class function Rule(RuleNumber: Integer): TVarFunc;
    class function SingleCell(Width: Integer): String;
    class function Generations(RuleNumber: Integer; const Initial: String): TSequence;

    class function Population(const Generation: String): Integer;
    class function PopulationOf: TVarFunc;      // generation -> live cell count
    class function CentreCell: TVarFunc;        // generation -> 0 / 1
    class function Render(const Generation: String): String;
    class function RenderOf: TVarFunc;
  end;

implementation

function CellValue(const Generation: String; Index: Integer): Integer;
var
  Width: Integer;
begin
  // Index is 0-based and wraps around the edges
  Width := Length(Generation);
  Index := ((Index mod Width) + Width) mod Width;
  if Generation[Index + 1] = '1' then
    Result := 1
  else
    Result := 0;
end;

class function TAutomaton.NextGeneration(const Generation: String;
  RuleNumber: Integer): String;
var
  i, Pattern: Integer;
begin
  Result := '';
  for i := 0 to Length(Generation) - 1 do
  begin
    Pattern := CellValue(Generation, i - 1) * 4 +
               CellValue(Generation, i) * 2 +
               CellValue(Generation, i + 1);
    if ((RuleNumber shr Pattern) and 1) = 1 then
      Result := Result + '1'
    else
      Result := Result + '0';
  end;
end;

class function TAutomaton.Rule(RuleNumber: Integer): TVarFunc;
var
  Number: Integer;
begin
  Number := RuleNumber;
  Result := function (Value: Variant): Variant
    var
      Gen: String;
    begin
      Gen := Value;
      Result := TAutomaton.NextGeneration(Gen, Number);
    end;
end;

class function TAutomaton.SingleCell(Width: Integer): String;
var
  i: Integer;
begin
  Result := '';
  for i := 0 to Width - 1 do
    if i = Width div 2 then
      Result := Result + '1'
    else
      Result := Result + '0';
end;

class function TAutomaton.Generations(RuleNumber: Integer;
  const Initial: String): TSequence;
begin
  Result := TSequence.Iterate(Initial, Rule(RuleNumber));
end;

class function TAutomaton.Population(const Generation: String): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(Generation) do
    if Generation[i] = '1' then
      Inc(Result);
end;

class function TAutomaton.PopulationOf: TVarFunc;
begin
  Result := function (Value: Variant): Variant
    var
      Gen: String;
    begin
      Gen := Value;
      Result := TAutomaton.Population(Gen);
    end;
end;

class function TAutomaton.CentreCell: TVarFunc;
begin
  Result := function (Value: Variant): Variant
    var
      Gen: String;
    begin
      Gen := Value;
      Result := CellValue(Gen, Length(Gen) div 2);
    end;
end;

class function TAutomaton.Render(const Generation: String): String;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(Generation) do
    if Generation[i] = '1' then
      Result := Result + '#'
    else
      Result := Result + ' ';
end;

class function TAutomaton.RenderOf: TVarFunc;
begin
  Result := function (Value: Variant): Variant
    var
      Gen: String;
    begin
      Gen := Value;
      Result := TAutomaton.Render(Gen);
    end;
end;

end.
