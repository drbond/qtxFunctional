unit functional.collections;

// ---------------------------------------------------------------------------
//  qtxFunctional - persistent (immutable) data structures  (Stage 4)
//
//  TImmutableList   a singly-linked cons list. Cons is O(1) and the new list
//                   physically shares every cell of the old one. SetNth copies
//                   only the cells before the change and shares the rest.
//
//  TPersistentMap   a String-keyed AVL tree with *path copying*:
//                   Put / Remove copy only the nodes on the path from the root
//                   to the change (O(log n)) and share every other subtree.
//                   Rebalancing rotations build new nodes from the pieces,
//                   so every previous version remains valid and unchanged.
//                   Height stays O(log n) even for keys inserted in order.
//
//  Nothing is ever mutated after construction, so any version can be shared
//  freely. CellsCreated / NodesCreated make the sharing measurable.
//
//  Pure Object Pascal - no inline JavaScript.
// ---------------------------------------------------------------------------

interface

uses
  qtx.sysutils,
  functional.functions,
  functional.fusion,
  functional.sequence;

type
  TStrArray = array of String;

  { TImmutableList }

  TImmutableList = class
  private
    FHead:  Variant;
    FTail:  TImmutableList;
    FCount: Integer;
    FEmpty: Boolean;
    class var FEmptyList: TImmutableList;
    constructor CreateCell(const Head: Variant; const Tail: TImmutableList;
      IsEmpty: Boolean);
    function GetHead: Variant;
    function GetTail: TImmutableList;
  public
    class var CellsCreated: Integer;

    class function Empty: TImmutableList;
    class function FromArray(const Values: TVarArray): TImmutableList;

    function Cons(const Value: Variant): TImmutableList;          // O(1), shares Self
    function Append(const Other: TImmutableList): TImmutableList; // copies Self, shares Other
    function SetNth(Index: Integer; const Value: Variant): TImmutableList;
    function Reverse: TImmutableList;
    function Map(const Fn: TVarFunc): TImmutableList;
    function Filter(const Predicate: TVarPredicate): TImmutableList;
    function Fold(const Seed: Variant; const Fn: TVarFoldFunc): Variant;
    function Nth(Index: Integer): Variant;

    function ToArray: TVarArray;
    function ToSequence: TSequence;      // feed a list into a fused pipeline
    function AsString: String;

    property Head: Variant read GetHead;
    property Tail: TImmutableList read GetTail;
    property Count: Integer read FCount;
    property IsEmpty: Boolean read FEmpty;
  end;

  { TPersistentMap }

  TMapNode = class
  private
    FKey:   String;
    FValue: Variant;
    FLeft:  TMapNode;
    FRight:  TMapNode;
    FHeight: Integer;
  public
    constructor Create(const Key: String; const Value: Variant;
      const Left, Right: TMapNode);
    property Key: String read FKey;
    property Value: Variant read FValue;
    property Left: TMapNode read FLeft;
    property Right: TMapNode read FRight;
    property Height: Integer read FHeight;
  end;

  TMapNodeArray = array of TMapNode;

  TPersistentMap = class
  private
    FRoot:  TMapNode;
    FCount: Integer;
    constructor CreateVersion(const Root: TMapNode; Count: Integer);
    class function NewNode(const Key: String; const Value: Variant;
      const Left, Right: TMapNode): TMapNode;
    class function InsertNode(const Node: TMapNode; const Key: String;
      const Value: Variant; var Added: Boolean): TMapNode;
    class function RemoveNode(const Node: TMapNode; const Key: String;
      var Removed: Boolean): TMapNode;
    class function MinNode(const Node: TMapNode): TMapNode;
    class function NodeHeight(const Node: TMapNode): Integer;
    class function Rebalance(const Key: String; const Value: Variant;
      const Left, Right: TMapNode): TMapNode;
    class function CheckNode(const Node: TMapNode; var Valid: Boolean): Integer;
    class procedure CollectNodes(const Node: TMapNode; var Nodes: TMapNodeArray);
    function FindNode(const Key: String): TMapNode;
  public
    class var NodesCreated: Integer;

    class function Empty: TPersistentMap;

    function Put(const Key: String; const Value: Variant): TPersistentMap;
    function Remove(const Key: String): TPersistentMap;
    function Get(const Key: String): Variant;
    function GetOrDefault(const Key: String; const Default: Variant): Variant;
    function ContainsKey(const Key: String): Boolean;

    function Keys: TStrArray;         // in sorted order
    function Values: TVarArray;       // in key order
    function Height: Integer;
    function IsBalanced: Boolean;     // verifies the AVL and ordering invariants
    function SharedNodes(const Other: TPersistentMap): Integer;
    function AsString: String;

    property Count: Integer read FCount;
    property Root: TMapNode read FRoot;   // read-only view, e.g. for drawing
  end;

implementation

{ TImmutableList }

constructor TImmutableList.CreateCell(const Head: Variant;
  const Tail: TImmutableList; IsEmpty: Boolean);
begin
  FHead := Head;
  FTail := Tail;
  FEmpty := IsEmpty;
  if IsEmpty then
    FCount := 0
  else
  begin
    FCount := Tail.Count + 1;
    Inc(CellsCreated);
  end;
end;

class function TImmutableList.Empty: TImmutableList;
begin
  if FEmptyList = nil then
    FEmptyList := TImmutableList.CreateCell(0, nil, True);
  Result := FEmptyList;
end;

class function TImmutableList.FromArray(const Values: TVarArray): TImmutableList;
var
  i: Integer;
begin
  Result := TImmutableList.Empty;
  for i := High(Values) downto 0 do
    Result := Result.Cons(Values[i]);
end;

function TImmutableList.GetHead: Variant;
begin
  if FEmpty then
    raise EFunctional.Create('TImmutableList.Head: list is empty');
  Result := FHead;
end;

function TImmutableList.GetTail: TImmutableList;
begin
  if FEmpty then
    raise EFunctional.Create('TImmutableList.Tail: list is empty');
  Result := FTail;
end;

function TImmutableList.Cons(const Value: Variant): TImmutableList;
begin
  Result := TImmutableList.CreateCell(Value, Self, False);
end;

function TImmutableList.Append(const Other: TImmutableList): TImmutableList;
var
  Items: TVarArray;
  i: Integer;
begin
  Items := ToArray;
  Result := Other;                      // the whole of Other is shared
  for i := High(Items) downto 0 do
    Result := Result.Cons(Items[i]);
end;

function TImmutableList.SetNth(Index: Integer; const Value: Variant): TImmutableList;
var
  Prefix: TVarArray;
  Cursor: TImmutableList;
  i: Integer;
begin
  if (Index < 0) or (Index >= FCount) then
    raise EFunctional.Create('TImmutableList.SetNth: index out of range');
  // Copy the cells before Index, then share everything after it
  Cursor := Self;
  for i := 0 to Index - 1 do
  begin
    Prefix.Add(Cursor.Head);
    Cursor := Cursor.Tail;
  end;
  Result := Cursor.Tail.Cons(Value);
  for i := High(Prefix) downto 0 do
    Result := Result.Cons(Prefix[i]);
end;

function TImmutableList.Reverse: TImmutableList;
var
  Cursor: TImmutableList;
begin
  Result := TImmutableList.Empty;
  Cursor := Self;
  while not Cursor.IsEmpty do
  begin
    Result := Result.Cons(Cursor.Head);
    Cursor := Cursor.Tail;
  end;
end;

function TImmutableList.Map(const Fn: TVarFunc): TImmutableList;
var
  Items: TVarArray;
  i: Integer;
begin
  Items := ToArray;
  for i := 0 to High(Items) do
    Items[i] := Fn(Items[i]);
  Result := TImmutableList.FromArray(Items);
end;

function TImmutableList.Filter(const Predicate: TVarPredicate): TImmutableList;
var
  Items, Kept: TVarArray;
  i: Integer;
begin
  Items := ToArray;
  for i := 0 to High(Items) do
    if Predicate(Items[i]) then
      Kept.Add(Items[i]);
  Result := TImmutableList.FromArray(Kept);
end;

function TImmutableList.Fold(const Seed: Variant; const Fn: TVarFoldFunc): Variant;
var
  Cursor: TImmutableList;
begin
  Result := Seed;
  Cursor := Self;
  while not Cursor.IsEmpty do
  begin
    Result := Fn(Result, Cursor.Head);
    Cursor := Cursor.Tail;
  end;
end;

function TImmutableList.Nth(Index: Integer): Variant;
var
  Cursor: TImmutableList;
  i: Integer;
begin
  if (Index < 0) or (Index >= FCount) then
    raise EFunctional.Create('TImmutableList.Nth: index out of range');
  Cursor := Self;
  for i := 1 to Index do
    Cursor := Cursor.Tail;
  Result := Cursor.Head;
end;

function TImmutableList.ToArray: TVarArray;
var
  Cursor: TImmutableList;
begin
  Cursor := Self;
  while not Cursor.IsEmpty do
  begin
    Result.Add(Cursor.Head);
    Cursor := Cursor.Tail;
  end;
end;

function TImmutableList.ToSequence: TSequence;
var
  Start: TImmutableList;
  NoStages: TFusionStages;
begin
  Start := Self;
  Result := TSequence.Create(
    procedure (const Sink: TVarSink)
    var
      Cursor: TImmutableList;
    begin
      Cursor := Start;
      while not Cursor.IsEmpty do
      begin
        if not Sink(Cursor.Head) then
          exit;
        Cursor := Cursor.Tail;
      end;
    end,
    'List[' + IntToStr(FCount) + ']', False, NoStages);
end;

function TImmutableList.AsString: String;
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

{ TMapNode }

constructor TMapNode.Create(const Key: String; const Value: Variant;
  const Left, Right: TMapNode);
var
  L, R: Integer;
begin
  FKey := Key;
  FValue := Value;
  FLeft := Left;
  FRight := Right;
  if Left = nil then L := 0 else L := Left.Height;
  if Right = nil then R := 0 else R := Right.Height;
  if L > R then
    FHeight := L + 1
  else
    FHeight := R + 1;
end;

{ TPersistentMap }

constructor TPersistentMap.CreateVersion(const Root: TMapNode; Count: Integer);
begin
  FRoot := Root;
  FCount := Count;
end;

class function TPersistentMap.Empty: TPersistentMap;
begin
  Result := TPersistentMap.CreateVersion(nil, 0);
end;

class function TPersistentMap.NewNode(const Key: String; const Value: Variant;
  const Left, Right: TMapNode): TMapNode;
begin
  Inc(NodesCreated);
  Result := TMapNode.Create(Key, Value, Left, Right);
end;

class function TPersistentMap.Rebalance(const Key: String; const Value: Variant;
  const Left, Right: TMapNode): TMapNode;
var
  L, R: TMapNode;
begin
  // Builds the node (Key, Value, Left, Right), rotating if the AVL balance
  // is broken. Rotations create NEW nodes from the pieces - nothing that
  // belongs to an older version is ever modified.
  L := Left;
  R := Right;

  if NodeHeight(L) > NodeHeight(R) + 1 then
  begin
    if NodeHeight(L.Left) >= NodeHeight(L.Right) then
      // Left-left: single right rotation
      Result := NewNode(L.Key, L.Value, L.Left, NewNode(Key, Value, L.Right, R))
    else
      // Left-right: double rotation
      Result := NewNode(L.Right.Key, L.Right.Value,
        NewNode(L.Key, L.Value, L.Left, L.Right.Left),
        NewNode(Key, Value, L.Right.Right, R));
  end
  else if NodeHeight(R) > NodeHeight(L) + 1 then
  begin
    if NodeHeight(R.Right) >= NodeHeight(R.Left) then
      // Right-right: single left rotation
      Result := NewNode(R.Key, R.Value, NewNode(Key, Value, L, R.Left), R.Right)
    else
      // Right-left: double rotation
      Result := NewNode(R.Left.Key, R.Left.Value,
        NewNode(Key, Value, L, R.Left.Left),
        NewNode(R.Key, R.Value, R.Left.Right, R.Right));
  end
  else
    Result := NewNode(Key, Value, L, R);
end;

class function TPersistentMap.InsertNode(const Node: TMapNode; const Key: String;
  const Value: Variant; var Added: Boolean): TMapNode;
begin
  if Node = nil then
  begin
    Added := True;
    exit(NewNode(Key, Value, nil, nil));
  end;
  // Copy this node (it is on the path), rebalance, share the untouched side
  if Key < Node.Key then
    Result := Rebalance(Node.Key, Node.Value,
      InsertNode(Node.Left, Key, Value, Added), Node.Right)
  else if Key > Node.Key then
    Result := Rebalance(Node.Key, Node.Value,
      Node.Left, InsertNode(Node.Right, Key, Value, Added))
  else
    Result := NewNode(Key, Value, Node.Left, Node.Right);   // replace value
end;

class function TPersistentMap.MinNode(const Node: TMapNode): TMapNode;
begin
  Result := Node;
  while Result.Left <> nil do
    Result := Result.Left;
end;

class function TPersistentMap.RemoveNode(const Node: TMapNode; const Key: String;
  var Removed: Boolean): TMapNode;
var
  Successor: TMapNode;
  Dummy: Boolean;
begin
  if Node = nil then
    exit(nil);

  if Key < Node.Key then
    exit(Rebalance(Node.Key, Node.Value,
      RemoveNode(Node.Left, Key, Removed), Node.Right));
  if Key > Node.Key then
    exit(Rebalance(Node.Key, Node.Value,
      Node.Left, RemoveNode(Node.Right, Key, Removed)));

  // Found it
  Removed := True;
  if Node.Left = nil then
    exit(Node.Right);          // shared, not copied
  if Node.Right = nil then
    exit(Node.Left);
  Successor := MinNode(Node.Right);
  Dummy := False;
  Result := Rebalance(Successor.Key, Successor.Value,
    Node.Left, RemoveNode(Node.Right, Successor.Key, Dummy));
end;

function TPersistentMap.Put(const Key: String; const Value: Variant): TPersistentMap;
var
  Added: Boolean;
  Root: TMapNode;
begin
  Added := False;
  Root := InsertNode(FRoot, Key, Value, Added);
  if Added then
    Result := TPersistentMap.CreateVersion(Root, FCount + 1)
  else
    Result := TPersistentMap.CreateVersion(Root, FCount);
end;

function TPersistentMap.Remove(const Key: String): TPersistentMap;
var
  Removed: Boolean;
  Root: TMapNode;
begin
  if not ContainsKey(Key) then
    exit(Self);                // nothing to change - share the whole version
  Removed := False;
  Root := RemoveNode(FRoot, Key, Removed);
  Result := TPersistentMap.CreateVersion(Root, FCount - 1);
end;

function TPersistentMap.FindNode(const Key: String): TMapNode;
begin
  Result := FRoot;
  while Result <> nil do
  begin
    if Key < Result.Key then
      Result := Result.Left
    else if Key > Result.Key then
      Result := Result.Right
    else
      exit;
  end;
end;

function TPersistentMap.Get(const Key: String): Variant;
var
  Node: TMapNode;
begin
  Node := FindNode(Key);
  if Node = nil then
    raise EFunctional.Create('TPersistentMap.Get: key "' + Key + '" not found');
  Result := Node.Value;
end;

function TPersistentMap.GetOrDefault(const Key: String; const Default: Variant): Variant;
var
  Node: TMapNode;
begin
  Node := FindNode(Key);
  if Node = nil then
    Result := Default
  else
    Result := Node.Value;
end;

function TPersistentMap.ContainsKey(const Key: String): Boolean;
begin
  Result := FindNode(Key) <> nil;
end;

class procedure TPersistentMap.CollectNodes(const Node: TMapNode;
  var Nodes: TMapNodeArray);
begin
  if Node = nil then
    exit;
  CollectNodes(Node.Left, Nodes);
  Nodes.Add(Node);
  CollectNodes(Node.Right, Nodes);
end;

function TPersistentMap.Keys: TStrArray;
var
  Nodes: TMapNodeArray;
  i: Integer;
begin
  CollectNodes(FRoot, Nodes);
  for i := 0 to High(Nodes) do
    Result.Add(Nodes[i].Key);
end;

function TPersistentMap.Values: TVarArray;
var
  Nodes: TMapNodeArray;
  i: Integer;
begin
  CollectNodes(FRoot, Nodes);
  for i := 0 to High(Nodes) do
    Result.Add(Nodes[i].Value);
end;

class function TPersistentMap.NodeHeight(const Node: TMapNode): Integer;
begin
  // Stored at construction time - O(1)
  if Node = nil then
    Result := 0
  else
    Result := Node.Height;
end;

class function TPersistentMap.CheckNode(const Node: TMapNode; var Valid: Boolean): Integer;
var
  L, R: Integer;
begin
  // Recomputes the true height and verifies the AVL invariants:
  // stored height is correct and the subtrees differ by at most one
  if Node = nil then
    exit(0);
  L := CheckNode(Node.Left, Valid);
  R := CheckNode(Node.Right, Valid);
  if L > R then
    Result := L + 1
  else
    Result := R + 1;
  if (Abs(L - R) > 1) or (Result <> Node.Height) then
    Valid := False;
  if (Node.Left <> nil) and (Node.Left.Key >= Node.Key) then
    Valid := False;
  if (Node.Right <> nil) and (Node.Right.Key <= Node.Key) then
    Valid := False;
end;

function TPersistentMap.Height: Integer;
begin
  Result := NodeHeight(FRoot);
end;

function TPersistentMap.IsBalanced: Boolean;
begin
  Result := True;
  CheckNode(FRoot, Result);
end;

function TPersistentMap.SharedNodes(const Other: TPersistentMap): Integer;
var
  Mine, Theirs: TMapNodeArray;
  i, j: Integer;
begin
  // Counts nodes that are physically the same object in both versions
  CollectNodes(FRoot, Mine);
  CollectNodes(Other.FRoot, Theirs);
  Result := 0;
  for i := 0 to High(Mine) do
    for j := 0 to High(Theirs) do
      if Mine[i] = Theirs[j] then
      begin
        Inc(Result);
        break;
      end;
end;

function TPersistentMap.AsString: String;
var
  Nodes: TMapNodeArray;
  Text: String;
  i: Integer;
begin
  CollectNodes(FRoot, Nodes);
  Result := '{';
  for i := 0 to High(Nodes) do
  begin
    if i > 0 then
      Result := Result + ', ';
    Text := Nodes[i].Value;
    Result := Result + Nodes[i].Key + ': ' + Text;
  end;
  Result := Result + '}';
end;

end.
