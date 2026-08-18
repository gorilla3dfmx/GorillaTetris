unit MainForm;

interface

{$DEFINE AUDIO}

{$IFDEF ANDROID}
  // By default we deactivate audio, because on some devices it causes issues.
  {$UNDEF AUDIO}
{$ENDIF}

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  System.Math.Vectors, System.Math, System.IOUtils, System.SyncObjs, FMX.Types3D,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Objects3D,
  FMX.Controls3D, FMX.StdCtrls, FMX.Layouts, FMX.Objects, FMX.Controls.Presentation,
  FMX.Gestures,
{$IFDEF AUDIO}
  Gorilla.Audio.FMOD,
{$ENDIF}
  Gorilla.Viewport, Gorilla.Camera, Gorilla.Utils.Timer, Gorilla.Light,
  Gorilla.Material.Default, Gorilla.Mesh, Gorilla.Cube, Gorilla.Plane,
  Gorilla.DefTypes, Gorilla.Material.Lambert, Gorilla.Material.Blinn;

// Basic constants so CreateGorillaScene compiles (board center usage)
const
  ROWS       = 20;   // Number of rows in the gaming field
  COLS       = 10;   // Number of columns in the gaming field
  CUBE_SIZE  = 1.0;  // Size of each cube placeable
  CUBE_SPACE = 0.05; // A tiny space between each cube for a more cubish look of the pieces.

type
  TCellKind = (ckNone, ckI, ckO, ckT, ckS, ckZ, ckJ, ckL);

  TRotation = 0..3;

  TPieceMatrix = array[0..3, 0..3] of Boolean;

  TPiece = record
    Kind   : TCellKind;
    Matrix : TPieceMatrix;
    X, Y   : Integer;
    Rot    : TRotation;
  end;

  TBoard = array[0..ROWS-1, 0..COLS-1] of TCellKind;
  TCubes = array[0..ROWS-1, 0..COLS-1] of TGorillaMeshInstance;

  PCubeArray = ^TCubeArray;
  TCubeArray = Array[TCellKind] of TGorillaCube;

  TForm1 = class(TForm)
    Image1: TImage;
    Image2: TImage;
    Image3: TImage;
    Rectangle1: TRectangle;
    ScoreLabel: TLabel;
    LevelLabel: TLabel;
    LinesLabel: TLabel;
    Image4: TImage;
    FinalScoreLabel: TLabel;
    GestureManager1: TGestureManager;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
    procedure FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);

    procedure ViewportTap(Sender: TObject; const Point: TPointF);
    procedure ViewportGesture(Sender: TObject; const EventInfo: TGestureEventInfo;
      var Handled: Boolean);

  private
    FGorilla : TGorillaViewport;
    FTimer   : TGorillaTimer;
    FAssetsPath : String;
    FDestroying : Boolean;

    FTarget  : TDummy;
    FCamera  : TGorillaCamera;
    FLight   : TGorillaLight;

    FBoard : TBoard;
    FCubes : TCubes;

    FActivePiece : TCellKind;
    FActiveX, FActiveY : Integer;
    FLeftHeld,
    FDownHeld,
    FRightHeld : Boolean;

    FHardDropExtraPoints,
    FHardDrop  : Boolean;

    FLastMove  : TDateTime;
    FWithGesture : Boolean;
    FCurrentPiece :TPiece;

    // We're working with instancing of template cubes, which is much faster,
    // than having 10 * 20 cubes rendered on each cycle.
    FTemplates: TCubeArray;
    FTemplatesElectric: TCubeArray;
    FGhostTemplate : TGorillaCube;

    // Active tetromino as 4 cubes
    FActiveCubes : array[0..3] of TGorillaMeshInstance;

    // Ghost cubes preview for the current piece
    FGhostCubes : array[0..3] of TGorillaMeshInstance;

    // Gravitation
    FPieceDropTimer : Single;   // Seconds since falling
    FPieceDropDelay : Single;   // Seconds per line (speed of level)

    // Additional variables for DAS/ARR
    FMoveTimer : Single; // Timer for horizontal movement
    FMoveDelay : Single; // Delay bevor the first repeat (DAS)
    FMoveRate  : Single; // Time between repetition (ARR)
    FMoveIntensity : Integer;
    FIsInitialMove : Boolean; // Flag, to mark the first movement
    FGameOver : Boolean;      // << Game-Over state variable - if this is true, the game ends

    // --- Linked labels for showing gaming stats
    FScoreLabel: TLabel;
    FLevelLabel: TLabel;
    FLinesLabel: TLabel;

    FScore: Integer;
    FLevel: Integer;
    FLinesCleared: Integer;

    // --- Variables for animations
    FAnimationTimer: Single; // Timer for the animation duration
    FIsAnimating: Boolean; // State indicating if the animation is running
    FAnimatedCubes: TArray<TGorillaMeshInstance>; // Array of animating cube instance
    FAnimatedVelocities: TArray<TVector3D>; // Array for starting speed
    FAnimatedBasePos: TArray<TPoint3D>; // Origin position for vibration
    FAnimatedVibrateDirs: TArray<TVector3D>; // Vibration direction per cube
    FAnimatedPhases: TArray<Single>; // Sinus-Vibration phases
    FExplosionTriggered: Boolean; // State indicating if the explosion was started
    FRemovedLines: TArray<Integer>; // Stores y-coordinates for deletable lines

    // Next-piece preview
    FNextPieces: array[0..1] of TCellKind;
    FPreviewCubes: array[0..1, 0..3] of TGorillaCube;

    // Bag7 Randomizer
    FBag: array[0..6] of TCellKind;
    FBagIndex: Integer; // Index on the next element in bag (0..6)

  {$IFDEF AUDIO}
    // Music and effects
    FAudioPlayer : TGorillaFMODAudioManager;
  {$ENDIF}

    // --- Shake-Animation for HardDrop ---
    FIsShaking: Boolean;
    FShakeTimer: Single;
    FShakeDuration: Single;
    FShakeOscillations: Integer; // Number of swingings
    FShakingCubes: TArray<TGorillaMeshInstance>;
    FShakeOrigPos: TArray<TVector3D>;
    FShakeAmplitudes: TArray<TVector3D>;
    FShakeBaseFreqs: TArray<TVector3D>;

    // --- Camera Shake ---
    FCameraOrigPos: TVector3D;
    FCameraShakeEnabled: Boolean;
    FCameraShakeAmplitude: TVector3D;
    FCameraShakeBaseFreq: TVector3D;

    // --- Drop-Animation after a line was cleared ---
    FIsDropping: Boolean;
    FDropTimer: Single;
    FDropDuration: Single;
    FDroppingCubes: TArray<TGorillaMeshInstance>;
    FDropStartPos: TArray<TVector3D>; // Dropping start position per cube
    FDropEndPos: TArray<TVector3D>; // Dropping end position per cube
    FDropDelay: TArray<Single>; // Dropping delay per cube

    // --- A global text to store the more complex electric shader effect, when
    // a line gets removed ---
    FElectricShader : TStringList;

    procedure ShuffleBag;
    procedure RefillBag;
    function DrawFromBag: TCellKind;

    function TryMove(dx,dy: Integer): Boolean;
    procedure InitBoard;

    procedure SpawnPiece;
    procedure LockPiece;

    procedure RedrawBoard;
    procedure RedrawActive;
    procedure RedrawGhost;
    procedure ClearLines;
    procedure UpdateStats;
    procedure UpdatePreview;

    procedure StartLineClearAnimation(const Lines: TArray<Integer>);
    procedure StartShakeBoard;
    procedure StartDropAnimation;

    procedure DoOnTick(Sender: TObject);
    procedure Refresh();

    procedure HandleGameOver;
    procedure Clear();

  protected
    procedure CreateGorillaScene;
  public
  end;

function Collides(const M: TPieceMatrix; X,Y: Integer; const Board: TBoard): Boolean;
procedure RotatePiece(var P: TPiece; Dir: Integer; const Board: TBoard);

var
  Form1: TForm1;

implementation

{$R *.fmx}

// Falling speeds for each level
const PieceDropDelays: array[0..20] of Single =
  (0.8, 0.717, 0.63, 0.55, 0.47, 0.39, 0.31, 0.23, 0.20, 0.16, 0.14, 0.12, 0.10,
   0.09, 0.08, 0.07, 0.06, 0.05, 0.04, 0.03, 0.02);

const
  ActivePieceEmission = $55000000;

  PieceColors: array[TCellKind] of TAlphaColor =
    ($44CCCCCC, // None
     $448ecae6, // Cyan
     $44ffee32, // Gelb
     $44c86bfa, // Lila
     $4490be6d, // Grün
     $44f94144, // Rot
     $44abc4ff, // Blau
     $44f8961e  // Orange
     );

const
  PieceShapes: array[TCellKind] of TPieceMatrix = (
    // ckNone dummy
    ((False,False,False,False),
     (False,False,False,False),
     (False,False,False,False),
     (False,False,False,False)),

    // I
    ((False,False,False,False),
     (True, True, True, True),
     (False,False,False,False),
     (False,False,False,False)),

    // O
    ((False,True, True,False),
     (False,True, True,False),
     (False,False,False,False),
     (False,False,False,False)),

    // T
    ((False,True, False,False),
     (True, True, True,False),
     (False,False,False,False),
     (False,False,False,False)),

    // S
    ((False, True, True,False),
     (True,  True, False,False),
     (False,False,False,False),
     (False,False,False,False)),

    // Z
    ((True,  True, False,False),
     (False, True, True,False),
     (False,False,False,False),
     (False,False,False,False)),

    // J
    ((True, False,False,False),
     (True, True, True,False),
     (False,False,False,False),
     (False,False,False,False)),

    // L
    ((False,False, True,False),
     (True, True, True,False),
     (False,False,False,False),
     (False,False,False,False))
  );

type
  TKickList = array[0..4] of TPoint;

const
  // JLSTZ-Kicks: FromRot x ToRot
  JLSTZ_Kicks: array[0..3,0..3] of TKickList = (
    ( // From 0
      ( (X:0;Y:0), (X:-1;Y:0), (X:-1;Y:1), (X:0;Y:-2), (X:-1;Y:-2) ), // 0->R
      ( (X:0;Y:0), (X:1;Y:0),  (X:1;Y:1),  (X:0;Y:-2), (X:1;Y:-2) ), // 0->L
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0) ),  // 0->2 (unused)
      ( (X:0;Y:0), (X:1;Y:0),  (X:1;Y:1),  (X:0;Y:-2), (X:1;Y:-2) )  // 0->L (duplicate, but defined)
    ),
    ( // From R
      ( (X:0;Y:0), (X:1;Y:0),  (X:1;Y:-1),   (X:0;Y:2),  (X:1;Y:2) ),  // R->0
      ( (X:0;Y:0), (X:1;Y:0),  (X:1;Y:1),  (X:0;Y:-2), (X:1;Y:-2) ), // R->L
      ( (X:0;Y:0), (X:1;Y:0),  (X:1;Y:1),  (X:0;Y:-2), (X:1;Y:-2) ), // R->2
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0) )   // R->L (dup)
    ),
    ( // From 2
      ( (X:0;Y:0), (X:1;Y:0),  (X:1;Y:-1), (X:0;Y:2),  (X:1;Y:2) ),  // 2->R
      ( (X:0;Y:0), (X:-1;Y:0), (X:-1;Y:-1),(X:0;Y:2),  (X:-1;Y:2) ), // 2->L
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0) ),  // 2->0 (dup)
      ( (X:0;Y:0), (X:-1;Y:0), (X:-1;Y:-1),(X:0;Y:2),  (X:-1;Y:2) )  // 2->L
    ),
    ( // From L
      ( (X:0;Y:0), (X:-1;Y:0), (X:-1;Y:1), (X:0;Y:-2), (X:-1;Y:-2) ), // L->0
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0) ),  // L->R (dup)
      ( (X:0;Y:0), (X:-1;Y:0), (X:-1;Y:1), (X:0;Y:-2), (X:-1;Y:-2) ), // L->2
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0),  (X:0;Y:0) )   // L->L
    )
  );

const
  I_Kicks: array[0..3,0..3] of TKickList = (
    ( // From 0
      ( (X:0;Y:0), (X:-2;Y:0), (X:1;Y:0), (X:-2;Y:-1), (X:1;Y:2) ), // 0->R
      ( (X:0;Y:0), (X:2;Y:0),  (X:-1;Y:0),(X:2;Y:1),   (X:-1;Y:-2)), // 0->L
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0), (X:0;Y:0),   (X:0;Y:0) ), // 0->2
      ( (X:0;Y:0), (X:-1;Y:0), (X:2;Y:0), (X:-1;Y:2),  (X:2;Y:-1) ) // 0->L
    ),
    ( // From R
      ( (X:0;Y:0), (X:2;Y:0),  (X:-1;Y:0),(X:2;Y:1),   (X:-1;Y:-2)), // R->0
      ( (X:0;Y:0), (X:-1;Y:0), (X:2;Y:0), (X:-1;Y:2),  (X:2;Y:-1) ), // R->2
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0), (X:0;Y:0),   (X:0;Y:0) ), // R->L
      ( (X:0;Y:0), (X:1;Y:0),  (X:-2;Y:0),(X:1;Y:-2),  (X:-2;Y:1) )  // R->L
    ),
    ( // From 2
      ( (X:0;Y:0), (X:1;Y:0),  (X:-2;Y:0),(X:1;Y:-2),  (X:-2;Y:1) ), // 2->R
      ( (X:0;Y:0), (X:-2;Y:0), (X:1;Y:0), (X:-2;Y:-1), (X:1;Y:2) ),  // 2->L
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0), (X:0;Y:0),   (X:0;Y:0) ),  // 2->0
      ( (X:0;Y:0), (X:2;Y:0),  (X:-1;Y:0),(X:2;Y:1),   (X:-1;Y:-2))  // 2->L
    ),
    ( // From L
      ( (X:0;Y:0), (X:-1;Y:0), (X:2;Y:0), (X:-1;Y:2),  (X:2;Y:-1) ), // L->0
      ( (X:0;Y:0), (X:1;Y:0),  (X:-2;Y:0),(X:1;Y:-2),  (X:-2;Y:1) ), // L->R
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0), (X:0;Y:0),   (X:0;Y:0) ), // L->2
      ( (X:0;Y:0), (X:0;Y:0),  (X:0;Y:0), (X:0;Y:0),   (X:0;Y:0) )   // L->L
    )
  );

procedure RotatePiece(var P: TPiece; Dir: Integer; const Board: TBoard);
var
  OldRot, NewRot: TRotation;
  NewMat: TPieceMatrix;
  x,y: Integer;
  Kicks: TKickList;
  dx,dy: Integer;
begin
  OldRot := P.Rot;
  NewRot := (OldRot + Dir + 4) mod 4;

  // Rotate matrix
  for y := 0 to 3 do
    for x := 0 to 3 do
      if Dir=1 then // rechts
        NewMat[x,3-y] := P.Matrix[y,x]
      else           // links
        NewMat[3-x,y] := P.Matrix[y,x];

  // Select kick table
  if P.Kind = ckI then
    Kicks := I_Kicks[P.Rot, NewRot]
  else
    Kicks := JLSTZ_Kicks[P.Rot, NewRot];

  // Test kick offsets
  for var k in Kicks do
  begin
    if not Collides(NewMat, P.X+k.X, P.Y+k.Y, Board) then
    begin
      P.Matrix := NewMat;
      P.Rot := NewRot;
      P.X := P.X + k.X;
      P.Y := P.Y + k.Y;
      Exit;
    end;
  end;
end;

function Collides(const M: TPieceMatrix; X,Y: Integer; const Board: TBoard): Boolean;
var i,j: Integer;
begin
  for j := 0 to 3 do
    for i := 0 to 3 do
      if M[j,i] then
      begin
        if (X+i<0) or (X+i>=COLS) or (Y+j>=ROWS) then
          Exit(True);
        if (Y+j>=0) and (Board[Y+j,X+i]<>ckNone) then
          Exit(True);
      end;

  Result := False;
end;

function TForm1.TryMove(dx, dy: Integer): Boolean;
begin
  dx := dx * FMoveIntensity;

  // Check collision a the end
  Result := not Collides(FCurrentPiece.Matrix, FCurrentPiece.X + dx, FCurrentPiece.Y + dy, FBoard);
  if Result then
  begin
    Inc(FCurrentPiece.X, dx);
    Inc(FCurrentPiece.Y, dy);
    RedrawActive;
  end
  else
  begin
    // If movement fails and it's a movement downwards, and the y-coordinate is
    // still in starting zone (above the gaming area)
    if (dy > 0) and (FCurrentPiece.Y < 0) then
    begin
      // Hide active cubes
      for var i := 0 to 3 do
        if Assigned(FActiveCubes[i]) then
        begin
          FActiveCubes[i].OwnerMesh.DeleteInstance(FActiveCubes[i].Index);
          FActiveCubes[i] := nil;
        end;

      HandleGameOver;

      // Important: no more movement here
      Exit;
    end;
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  Randomize;

{$IFDEF MSWINDOWS}
  FAssetsPath := '';
{$ENDIF}
{$IFDEF LINUX}
  FAssetsPath := '';
{$ENDIF}
{$IFDEF ANDROID}
  FAssetsPath := IncludeTrailingPathDelimiter(System.IOUtils.TPath.GetHomePath());
{$ENDIF}

{$IFDEF AUDIO}
  FAudioPlayer := TGorillaFMODAudioManager.Create(Self);
  FAudioPlayer.AutoUpdate := true;
  var LSoundItem := FAudioPlayer.LoadSoundItemFromFile(FAssetsPath + 'blocks_style.wav') as TGorillaFMODSoundItem;
  LSoundItem.Loop := true;
  LSoundItem.LoopCount := -1;
  LSoundItem.Play();
{$ENDIF}

  // Initialize stats
  FScore := 0;
  FLevel := 0;
  FLinesCleared := 0;

  FPieceDropDelay := 0.9;
  FPieceDropTimer := 0;

  // Initialize DAS/ARR values
  FMoveDelay := 0.2; // 200 ms delay
  FMoveRate := 0.05; // 50 ms between repetition
  FMoveTimer := 0;
  FMoveIntensity := 1;
  FIsInitialMove := False;
  FGameOver := False; // Reset on start

  FIsShaking := False;
  FShakeTimer := 0;
  FShakeDuration := 0.5;
  FShakeOscillations := 4;

  FCameraShakeEnabled := True;
  // Standard amplitude: a bit smaller than the cube amplitude: can be adjusted, if you like
  FCameraShakeAmplitude := Vector3D(0.25, 0.25, 0.0); // X,Y,Z in scene units
  FCameraShakeBaseFreq := Vector3D(1.0, 1.2, 0.9);    // Basis frequencies (multiplied with oscillations)

  // create viewport at runtime and fill the form
  FGorilla := TGorillaViewport.Create(Self);
  FGorilla.Parent := Self;
  FGorilla.Align := TAlignLayout.Contents;
  FGorilla.UsingDesignCamera := False;
  FGorilla.EmissiveBlur := 3;
  FGorilla.FrustumCulling := false;

  FGorilla.Touch.GestureManager := GestureManager1;
  FGorilla.Touch.StandardGestures := [TStandardGesture.sgLeft,
    TStandardGesture.sgRight, TStandardGesture.sgUp, TStandardGesture.sgDown];
  FGorilla.Touch.InteractiveGestures := [TInteractiveGesture.Rotate];
  FGorilla.OnGesture := ViewportGesture;
  FGorilla.OnTap := ViewportTap;

  // Manual movement via GorillaTimer (fixed ~60 fps)
  FTimer := TGorillaTimer.Create;
  FTimer.Interval := 16; // ~60 FPS
  FTimer.OnTimer := DoOnTick;
  FTimer.Start;

  Rectangle1.Parent := FGorilla;
  FScoreLabel := ScoreLabel;
  FLevelLabel := LevelLabel;
  FLinesLabel := LinesLabel;

  Image4.Parent := FGorilla;
  Image4.Visible := false;

  CreateGorillaScene;
  InitBoard;

  // Initialize Bag7
  RefillBag;

  // Initialize next pieces from bag
  FNextPieces[0] := DrawFromBag;
  FNextPieces[1] := DrawFromBag;
  UpdatePreview;

  SpawnPiece;

  UpdateStats;
  FPieceDropDelay := PieceDropDelays[FLevel];
end;

procedure TForm1.CreateGorillaScene;
var
  leftBorder, rightBorder, backPlane: TGorillaCube;
  borderMat, backMat: TGorillaDefaultMaterialSource;
  borderThickness, backDepth: Single;
  i: Integer;
begin
  // Create a dummy as camera target at the board center
  FTarget := TDummy.Create(FGorilla);
  FTarget.Parent := FGorilla;
  FTarget.Position.Point := Point3D(COLS / 2, ROWS / 2, 0); // forward declare via consts below

  // Create a Gorilla camera as child of target (orbit-style) and link to viewport
  FCamera := TGorillaCamera.Create(FTarget);
  FCamera.Parent := FTarget;
{$IFDEF ANDROID}
  FCamera.Position.Point := Point3D(0, 0, 45); // offset back on Z
{$ELSE}
  FCamera.Position.Point := Point3D(0, 0, 28); // offset back on Z
{$ENDIF}
  FCamera.FOV := 45;
  FCamera.Target := FTarget;    // << link target so it always looks at board center

  FGorilla.Camera := FCamera;   // << link camera to viewport
  FGorilla.UsingDesignCamera := false;

  // Save the original position of the camera for shaking-restore
  FCameraOrigPos := FCamera.Position.Point;

  FLight := TGorillaLight.Create(FCamera);
  FLight.Parent := FCamera;
  FLight.LightType := TLightType.Point;

  // Instead of loading the texture directly into a skybox we use 4 planes
  // we recognized issues on Android with the cubemap skybox
  // Also is unnecessary to render the top and bottom.
  // Anstatt einer Skybox erzeugen wir nur die notwendigen 4 Seiten
  var LPlane := TGorillaPlane.Create(FGorilla);
  LPlane.Parent := FGorilla;
  LPlane.SetSize(200, 200, 1);
  LPlane.Position.Point := Point3D(0, 0, -100);

  var LPlaneMat := TGorillaDefaultMaterialSource.Create(LPlane);
  LPlaneMat.Parent := LPlane;
  LPlaneMat.UseTexture0 := true;
{$IFDEF ANDROID}
  // On Android we're using a lower resolution of the skybox image
  LPlaneMat.Texture.LoadFromFile(FAssetsPath + 'Skybox.jpg');
{$ELSE}
  LPlaneMat.Texture.LoadFromFile(FAssetsPath + 'Skybox.png');
{$ENDIF}
  LPlane.MaterialSource := LPlaneMat;

  var LPlaneItm := LPlane.AddInstanceItem('RightPlane');
  LPlaneItm.Position.Point := Point3D(100, 0, 0);
  LPlaneItm.Scale.Point := Point3D(200, 200, 1);
  LPlaneItm.RotationAngle.Y := -90;

  LPlaneItm := LPlane.AddInstanceItem('FrontPlane');
  LPlaneItm.Position.Point := Point3D(0, 0, 100);
  LPlaneItm.Scale.Point := Point3D(200, 200, 1);
  LPlaneItm.RotationAngle.Y := 180;

  LPlaneItm := LPlane.AddInstanceItem('LeftPlane');
  LPlaneItm.Position.Point := Point3D(-100, 0, 0);
  LPlaneItm.Scale.Point := Point3D(200, 200, 1);
  LPlaneItm.RotationAngle.Y := 270;

  // Create a floor which we can animate
  var LFloor := TGorillaPlane.Create(FGorilla);
  LFloor.Parent := FGorilla;
  LFloor.RotationAngle.X := 90;
  LFloor.SetSize(200, 200, 1);
  LFloor.Position.Point := Point3D(0, 22.5, 0);
{$IFDEF ANDROID}
  // Not sure, why a default material is needed on Android
  var LFloorMat := TGorillaDefaultMaterialSource.Create(LFloor);
{$ELSE}
  // Create a simple lambert texture material with a expanded shader.
  var LFloorMat := TGorillaLambertMaterialSource.Create(LFloor);
{$ENDIF}
  LFloorMat.Parent := LFloor;
  LFloorMat.UseTexture0 := true;
  LFloorMat.Texture.LoadFromFile(FAssetsPath + 'Floor.jpg');

  // Write a small shader to animate the floor texture.
  // We need to activate time-measurement, otherwise "_TimeInfo" will not be set
  LFloorMat.MeasureTime := true;
  var LStr := TStringList.Create();
  try
    LStr.Text :=
      '''
      void SurfaceShader(inout TLocals DATA){
        vec2 l_TexOfs = DATA.TexCoord0.xy;

        float iTime = mod(mod(_TimeInfo.y, 360.0) * 0.2, 0.5);
        l_TexOfs += vec2(0.0, iTime);
        DATA.BaseColor.rgb = tex2D(_Texture0, l_TexOfs).rgb;
      }
      ''';
    LFloorMat.SurfaceShader := LStr;
  finally
    FreeAndNil(LStr);
  end;

  LFloor.MaterialSource := LFloorMat;

  // https://www.shadertoy.com/view/4scGWj
  FElectricShader := TStringList.Create();
  FElectricShader.Text :=
    '''
    vec3 random3(vec3 c) {
      float j = 4096.0*sin(dot(c,vec3(17.0, 59.4, 15.0)));
      vec3 r;
      r.z = fract(512.0*j);
      j *= .125;
      r.x = fract(512.0*j);
      j *= .125;
      r.y = fract(512.0*j);
      return r-0.5;
    }

    const float F3 =  0.3333333;
    const float G3 =  0.1666667;

    float simplex3d(vec3 p) {
       vec3 s = floor(p + dot(p, vec3(F3)));
       vec3 x = p - s + dot(s, vec3(G3));

       vec3 e = step(vec3(0.0), x - x.yzx);
       vec3 i1 = e*(1.0 - e.zxy);
       vec3 i2 = 1.0 - e.zxy*(1.0 - e);

       vec3 x1 = x - i1 + G3;
       vec3 x2 = x - i2 + 2.0*G3;
       vec3 x3 = x - 1.0 + 3.0*G3;

       vec4 w, d;

       w.x = dot(x, x);
       w.y = dot(x1, x1);
       w.z = dot(x2, x2);
       w.w = dot(x3, x3);

       w = max(0.6 - w, 0.0);

       d.x = dot(random3(s), x);
       d.y = dot(random3(s + i1), x1);
       d.z = dot(random3(s + i2), x2);
       d.w = dot(random3(s + 1.0), x3);

       w *= w;
       w *= w;
       d *= w;

       return dot(d, vec4(52.0));
    }

    float noise(vec3 m) {
        return   0.5333333*simplex3d(m)
          +0.2666667*simplex3d(2.0*m)
          +0.1333333*simplex3d(4.0*m)
          +0.0666667*simplex3d(8.0*m);
    }

    void SurfaceShader(inout TLocals DATA){
      float iTime = mod(_TimeInfo.y, 360.0);

      vec3 p3 = vec3(DATA.TexCoord0.xy, iTime);
      float intensity = noise(vec3(p3 + 12.0)) * 10.0;
      vec2 uv = DATA.TexCoord0.xy;
      uv = uv * 2.0 - 1.0;

      float t = clamp((uv.x * -uv.x * 0.01) + 0.15, 0., 1.);
      float y = abs(intensity * -t + uv.y * 0.5);

      float g = pow(y, 0.2);

      vec3 col = vec3(1.70, 1.48, 1.78);
      col = col * -g + col;
      col = col * col;
      col = col * col;

      DATA.BaseColor.rgb += col;
    }
    ''';

  // --- Visual borders / background for board size ---
  borderMat := TGorillaLambertMaterialSource.Create(FGorilla);
  borderMat.Parent := FGorilla;
  borderMat.Diffuse := $ff094e86;
  borderMat.Emissive := $00000000;
  borderMat.UseTexture0 := false;

  backMat := TGorillaLambertMaterialSource.Create(FGorilla);
  backMat.Parent := FGorilla;
  backMat.Diffuse := $ff094e86;
  backMat.Emissive := $00000000;
  backMat.UseTexture0 := false;

  borderThickness := 0.25;
  backDepth := 0.1;

  leftBorder := TGorillaCube.Create(FGorilla);
  leftBorder.Parent := FGorilla;
  leftBorder.SetSize(borderThickness, ROWS + 0.5, 1.5);
  leftBorder.Position.Point := Point3D(-0.5, (ROWS / 2) - 0.5, 0);
  leftBorder.MaterialSource := borderMat;
  leftBorder.SetOpacityValue(0.6);
  leftBorder.SetHitTestValue(false);
  leftBorder.Visible := True;

  rightBorder := TGorillaCube.Create(FGorilla);
  rightBorder.Parent := FGorilla;
  rightBorder.SetSize(borderThickness, ROWS + 0.5, 1.5);
  rightBorder.Position.Point := Point3D(COLS - 0.5, (ROWS / 2) - 0.5, 0);
  rightBorder.MaterialSource := borderMat;
  rightBorder.SetOpacityValue(0.6);
  rightBorder.SetHitTestValue(false);
  rightBorder.Visible := True;

  backPlane := TGorillaCube.Create(FGorilla);
  backPlane.Parent := FGorilla;
  backPlane.SetSize(COLS + 2, ROWS + 2, backDepth);
  backPlane.Position.Point := Point3D((COLS / 2) - 0.5, (ROWS / 2) - 0.5, -1);
  backPlane.MaterialSource := backMat;
  backPlane.SetOpacityValue(0.45);
  backPlane.SetHitTestValue(false);
  backPlane.Visible := True;

  // Creating templates for our cubes
  for var ck := Low(TCellKind) to High(TCellKind) do
  begin
    FTemplates[ck] := TGorillaCube.Create(FGorilla);
    FTemplates[ck].Parent := FGorilla;
    FTemplates[ck].SetSize(0.98, 0.98, 0.98);
    FTemplates[ck].Visible := true;
    FTemplates[ck].SetHitTestValue(false);
    FTemplates[ck].Position.Y := -100;

    if ck = ckNone then
      FTemplates[ck].SetOpacityValue(0);

    var mat := TGorillaBlinnMaterialSource.Create(FGorilla);
    mat.ShadingModel := TGorillaShadingModel.smBlinnPhong;
    mat.UseLighting := true;
    mat.UseSpecular := true;
    mat.UseTexture0 := false;
    mat.Parent := FGorilla;
    mat.Diffuse  := $FF0D1224;
    mat.Emissive := (PieceColors[ck] and $00FFFFFF) or ActivePieceEmission;
    FTemplates[ck].MaterialSource := mat;
  end;

  // Default cubes with electric effect
  for var ck := Low(TCellKind) to High(TCellKind) do
  begin
    FTemplatesElectric[ck] := TGorillaCube.Create(FGorilla);
    FTemplatesElectric[ck].Parent := FGorilla;
    FTemplatesElectric[ck].SetSize(0.98, 0.98, 0.98);
    FTemplatesElectric[ck].Visible := true;
    FTemplatesElectric[ck].SetHitTestValue(false);
    FTemplatesElectric[ck].Position.Y := -100;

    if ck = ckNone then
      FTemplatesElectric[ck].SetOpacityValue(0);

    var mat := TGorillaBlinnMaterialSource.Create(FGorilla);
    mat.ShadingModel := TGorillaShadingModel.smBlinnPhong;
    mat.UseLighting := true;
    mat.UseSpecular := true;
    mat.UseTexture0 := false;
    mat.Parent := FGorilla;
    mat.Diffuse  := $FF0D1224;
    mat.Emissive := (PieceColors[ck] and $00FFFFFF) or ActivePieceEmission;

    mat.MeasureTime := true;
    mat.SurfaceShader := FElectricShader;

    FTemplatesElectric[ck].MaterialSource := mat;
  end;

  // Create ghost cube template
  FGhostTemplate := TGorillaCube.Create(FGorilla);
  FGhostTemplate.Parent := FGorilla;
  FGhostTemplate.SetSize(0.98,0.98,0.98);
  FGhostTemplate.Visible := true;
  FGhostTemplate.SetOpacityValue(0.5);
  FGhostTemplate.SetHitTestValue(false);
  FGhostTemplate.Position.Y := -100;

  var mat := TGorillaBlinnMaterialSource.Create(FGorilla);
  mat.Parent := FGorilla;
  mat.Diffuse := $FF888888;
  mat.Emissive := 0;
  mat.UseTexture0 := false;

  FGhostTemplate.MaterialSource := mat;

  // --- Create preview cubes for the next 2 pieces ---
  for i := 0 to 1 do
  begin
    for var j := 0 to 3 do
    begin
      // Placed on the left side and much smaller
      FPreviewCubes[i,j] := TGorillaCube.Create(FGorilla);
      FPreviewCubes[i,j].Parent := FGorilla;
      FPreviewCubes[i,j].SetSize(0.5, 0.5, 0.5);
      FPreviewCubes[i,j].Visible := False;

      // Create a different material for a different look
      var pMat := TGorillaDefaultMaterialSource.Create(FGorilla);
      pMat.Parent := FGorilla;
      pMat.ShadingModel := TGorillaShadingModel.smBlinnPhong;
      pMat.UseLighting := true;
      pMat.UseSpecular := true;
      pMat.Diffuse := $FF5D41DF;
      pMat.Emissive := $00000000;

      FPreviewCubes[i,j].MaterialSource := pMat;
      FPreviewCubes[i,j].SetOpacityValue(0.85);
      FPreviewCubes[i,j].SetHitTestValue(false);
    end;
  end;

end;

procedure TForm1.UpdateStats;
begin
  FScoreLabel.Text := 'Score: ' + IntToStr(FScore);
  FLevelLabel.Text := 'Level: ' + IntToStr(FLevel);
  FLinesLabel.Text := 'Lines: ' + IntToStr(FLinesCleared);
end;

procedure TForm1.DoOnTick(Sender: TObject);
const DT = 1/60;
const
  VIBRATE_TIME = 0.4; // Seconds of vibration before the explosion
  VIBRATE_AMPLITUDE = 0.15; // maximum displacement of vibration
  VIBRATE_FREQ = 50.0; // vibration frequency (Hz)
  EXPLOSION_DURATION = 0.65; // Total duration of vibration and explosion
var
  vibrOff: TPoint3D;
  phase: Single;
var
  i: Integer;
  pos: TVector3D;
  x,y: Integer;
  amplitude: Single;
begin
  if FDestroying then
    Exit;

  // if GameOver is set, no more game logic, but finish the animation
  if FGameOver and not FIsAnimating then
  begin
    Refresh();
    Exit;
  end;

  // If animation is running, only handle this one and exit
  if FIsAnimating then
  begin
  {$IFDEF AUDIO}
    // Free the previously loaded item
    var LPrevItem := FAudioPlayer.GetSoundItemByFilename(FAssetsPath + 'row_clear.wav');
    if Assigned(LPrevItem) then
      FAudioPlayer.Sounds.Delete(LPrevItem.Index);

    var LItem := FAudioPlayer.LoadSoundItemFromFile(FAssetsPath + 'row_clear.wav');
    LItem.Play;
  {$ENDIF}

    FAnimationTimer := FAnimationTimer + DT;
    amplitude := VIBRATE_AMPLITUDE * abs(sin(FAnimationTimer) * 2);

    // Animation of exploding cubes, starting with vibration and ending in an explosion
    for i := 0 to High(FAnimatedCubes) do
    begin
      if Assigned(FAnimatedCubes[i]) then
      begin
        // If we're in a vibration phase, cube shaking in place.
        if FAnimationTimer < VIBRATE_TIME then
        begin
          phase := FAnimatedPhases[i];
          // sinus based vibration along a tiny random direction
          vibrOff := Point3D(
            FAnimatedVibrateDirs[i].X * Sin((FAnimationTimer * VIBRATE_FREQ) + phase) * amplitude,
            FAnimatedVibrateDirs[i].Y * Sin((FAnimationTimer * VIBRATE_FREQ) + phase) * amplitude,
            FAnimatedVibrateDirs[i].Z * Sin((FAnimationTimer * VIBRATE_FREQ) + phase) * amplitude
          );
          FAnimatedCubes[i].Position.Point := Point3D(
            FAnimatedBasePos[i].X + vibrOff.X,
            FAnimatedBasePos[i].Y + vibrOff.Y,
            FAnimatedBasePos[i].Z + vibrOff.Z
          );

          Continue;
        end;

        // Since vibration phase is done, run the explosion once.
        if (not FExplosionTriggered) then
        begin
          // Create a random explosion speed for each animated cube
          for var j := 0 to High(FAnimatedVelocities) do
          begin
            if Assigned(FAnimatedCubes[j]) then
            begin
              FAnimatedVelocities[j] := Vector3D(
                (RandomRange(-400, 400) / 100) * (1 + RandomRange(0,200)/100), // X
                (RandomRange(-100, 300) / 100) * (1 + RandomRange(0,200)/100), // Y
                (RandomRange(-400, 400) / 100) * (1 + RandomRange(0,200)/100)  // Z
              );
            end;
          end;
          FExplosionTriggered := True;

        {$IFDEF AUDIO}
          // Add your individual explosion sound here besides the row-clear sound.
//          var LItem := FAudioPlayer.LoadSoundItemFromFile(FAssetsPath + 'explode.wav');
//          if Assigned(LItem) then LItem.Play;
        {$ENDIF}
        end;

        // Regular movement after explosion
        pos := FAnimatedCubes[i].Position.Point;
        pos.X := pos.X + FAnimatedVelocities[i].X * DT * 5;
        pos.Y := pos.Y + FAnimatedVelocities[i].Y * DT * 5;
        pos.Z := pos.Z + FAnimatedVelocities[i].Z * DT * 5;
        FAnimatedCubes[i].Position.Point := pos;
      end;
    end;

    // Finish the animation and update gaming area, when the timer expired.
    if FAnimationTimer >= EXPLOSION_DURATION then
    begin
      FIsAnimating := False;

      // Free the cube instances after they exploded
      for i := 0 to High(FAnimatedCubes) do
      begin
        if Assigned(FAnimatedCubes[i]) then
        begin
          FAnimatedCubes[i].OwnerMesh.DeleteInstance(FAnimatedCubes[i].Index);
          FAnimatedCubes[i] := nil;
        end;
      end;
      SetLength(FAnimatedCubes, 0);
      SetLength(FAnimatedVelocities, 0);

      StartDropAnimation;
    end;

    Refresh();
    Exit;
  end;

  // --- Shake-Animation (HardDrop) ---
  if FIsShaking then
  begin
  {$IFDEF AUDIO}
    // Free the previously loaded item
    var LPrevItem := FAudioPlayer.GetSoundItemByFilename(FAssetsPath + 'harddrop_thud.wav');
    if Assigned(LPrevItem) then
      FAudioPlayer.Sounds.Delete(LPrevItem.Index);

    var LItem := FAudioPlayer.LoadSoundItemFromFile(FAssetsPath + 'harddrop_thud.wav');
    LItem.Play;
  {$ENDIF}

    FShakeTimer := FShakeTimer + DT;
    var t := FShakeTimer / FShakeDuration;
    if t > 1 then t := 1;

    //
    // Damping factor: smooth decay (use quadratic damping for softer end)
    var damp := (1 - t) * (1 - t); // square -> slower decay

    // For multiple back-and-forth oscillations, we use:
    // angle = 2*pi * Oscillations * t * baseFreqMultiplier
    // where baseFreq varies per cube (FShakeBaseFreqs)
    for i := 0 to High(FShakingCubes) do
    begin
      if Assigned(FShakingCubes[i]) then
      begin
        var orig := FShakeOrigPos[i];
        var amp := FShakeAmplitudes[i];
        var bf := FShakeBaseFreqs[i];

        // Calculate angular progression: 2*pi * Osc * (t) * baseFreq
        // t is 0..1 over the entire duration -> this creates exactly FShakeOscillations cycles
        var angleX := 2 * Pi * (FShakeOscillations * t) * bf.X;
        var angleY := 2 * Pi * (FShakeOscillations * t) * bf.Y;
        var angleZ := 2 * Pi * (FShakeOscillations * t) * bf.Z;

        // Sine-based back/forth, multiplied by damping
        var ox := Sin(angleX) * amp.X * damp;
        var oy := Sin(angleY) * amp.Y * damp;
        var oz := Sin(angleZ) * amp.Z * damp;

        FShakingCubes[i].Position.Point := Point3D(orig.X + ox, orig.Y + oy, orig.Z + oz);
      end;
    end;

    // --- Move camera synchronously to Block-Shake ---
    if FCameraShakeEnabled and Assigned(FCamera) then
    begin
      // We use the same t (0..1) and damp factor as for the cubes
      // angle = 2*pi * Oscillations * t * baseFreq
      var camAngleX := 2 * Pi * (FShakeOscillations * t) * FCameraShakeBaseFreq.X;
      var camAngleY := 2 * Pi * (FShakeOscillations * t) * FCameraShakeBaseFreq.Y;
      var camAngleZ := 2 * Pi * (FShakeOscillations * t) * FCameraShakeBaseFreq.Z;

      // Sinus based offset
      var camOx := Sin(camAngleX) * FCameraShakeAmplitude.X * damp;
      var camOy := Sin(camAngleY) * FCameraShakeAmplitude.Y * damp;
      var camOz := Sin(camAngleZ) * FCameraShakeAmplitude.Z * damp;

      // Set the camera position relative to the original position
      FCamera.Position.Point := Point3D(FCameraOrigPos.X + camOx,
                                        FCameraOrigPos.Y + camOy,
                                        FCameraOrigPos.Z + camOz);
    end;

    // End of animation: Restore positions and delete lines/continue
    if FShakeTimer >= FShakeDuration then
    begin
      for i := 0 to High(FShakingCubes) do
      begin
        if Assigned(FShakingCubes[i]) then
        begin
          var p := FShakeOrigPos[i];
          FShakingCubes[i].Position.Point := Point3D(Round(p.X), Round(p.Y), Round(p.Z));
        end;
      end;

      // Cleaning up the shake arrays
      SetLength(FShakingCubes, 0);
      SetLength(FShakeOrigPos, 0);
      SetLength(FShakeAmplitudes, 0);
      SetLength(FShakeBaseFreqs, 0);
      FIsShaking := False;
      FShakeTimer := 0;

      // Now check / delete lines (this was originally planned in the LockPiece)
      ClearLines;

      // Restore camera exact
      if FCameraShakeEnabled and Assigned(FCamera) then
      begin
        FCamera.Position.Point := Point3D(Round(FCameraOrigPos.X), Round(FCameraOrigPos.Y), Round(FCameraOrigPos.Z));
      end;
    end;

    Refresh();
    Exit; // While shake no more game logic
  end;

  // --- Drop-Animation after line clear ---
  if FIsDropping then
  begin
    FDropTimer := FDropTimer + DT;
    var allDone := True;

    for i := 0 to High(FDroppingCubes) do
    begin
      var cube := FDroppingCubes[i];
      if not Assigned(cube) then Continue;

      var delay := FDropDelay[i];
      var localT := (FDropTimer - delay) / FDropDuration;

      if localT < 0 then
      begin
        allDone := False;
        Continue; // cube is still waiting
      end;

      if localT >= 1 then
        localT := 1
      else
        allDone := False;

      // Smooth easing (Quadratic In)
      var easedT := localT * localT;

      var startP := FDropStartPos[i];
      var endP := FDropEndPos[i];

      var newY := startP.Y + (endP.Y - startP.Y) * easedT;
      var newX := endP.X;
      var newZ := endP.Z;

      cube.Position.Point := Point3D(newX, newY, newZ);
    end;

    if allDone then
    begin
      // Cleanup
      for i := 0 to High(FDroppingCubes) do
        if Assigned(FDroppingCubes[i]) then
          FDroppingCubes[i].Position.Point := FDropEndPos[i];

      SetLength(FDroppingCubes, 0);
      SetLength(FDropStartPos, 0);
      SetLength(FDropEndPos, 0);
      SetLength(FDropDelay, 0);

      FIsDropping := False;

      // Update + add new piece, since not game over
      RedrawBoard;
      UpdateStats;
      if not FGameOver then
        SpawnPiece;
    end;

    Refresh();
    Exit; // While dropping no more gravitation or inputs
  end;

  // --- Gravitation logic and DAS/ARR ---
  if FDownHeld or FHardDrop then
  begin
    if not TryMove(0,1) then
      LockPiece;
  end
  else
  begin
    FPieceDropTimer := FPieceDropTimer + DT;
    if FPieceDropTimer >= FPieceDropDelay then
    begin
      if not TryMove(0,1) then
        LockPiece;
      FPieceDropTimer := 0;
    end;
  end;

  if FLeftHeld or FRightHeld then
  begin
    FMoveTimer := FMoveTimer + DT;
    if not FIsInitialMove then
    begin
      FIsInitialMove := True;
      if FLeftHeld then TryMove(1, 0);
      if FRightHeld then TryMove(-1, 0);
      FMoveTimer := 0;
      FMoveIntensity := 1;
    end
    else
    begin
      var delay := FMoveDelay;
      if FMoveTimer >= delay then
      begin
        if FLeftHeld then TryMove(1, 0);
        if FRightHeld then TryMove(-1, 0);
        FMoveTimer := delay - FMoveRate;
      end;
    end;

    if FWithGesture then
    begin
      // Because we're using gestures on Android, we need to reset our flags
      // if they were enabled in the gesture callback
      if FLeftHeld then
      begin
        FLeftHeld := False;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;

      if FRightHeld then
      begin
        FRightHeld := False;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;

      FDownHeld := False;
      FWithGesture := false;
    end;
  end;

  Refresh();
end;

procedure TForm1.Refresh();
begin
{$IFDEF ANDROID}
  // Because Android rendering is event-based - we need to invalidate the scene
  // on each tick
  FGorilla.Invalidate();
{$ENDIF}
{$IFDEF LINUX}
  // Because Linux rendering is event-based - we need to invalidate the scene
  // on each tick
  FGorilla.Invalidate();
{$ENDIF}
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FDestroying := true;
  Clear;

  if Assigned(FTimer) then
  begin
    if FTimer.Started then
    begin
      FTimer.Terminate;
      FTimer.WaitFor;
    end;
    FTimer.Free;
  end;
end;

procedure TForm1.ViewportTap(Sender: TObject; const Point: TPointF);
var LVwPrtCtr : TPointF;
begin
  LVwPrtCtr := TPointF.Create(FGorilla.Width / 2, FGorilla.Height / 2);
  if Point.X > LVwPrtCtr.X then
  begin
    FRightHeld := True;
    FIsInitialMove := False;
    FMoveTimer := 0;
    FMoveIntensity := 1;
  end
  else if Point.X < LVwPrtCtr.X then
  begin
    FLeftHeld := True;
    FIsInitialMove := False;
    FMoveTimer := 0;
    FMoveIntensity := 1;
  end;

  FWithGesture := true;
end;

procedure TForm1.ViewportGesture(Sender: TObject;
  const EventInfo: TGestureEventInfo; var Handled: Boolean);
begin
  if FGameOver then
  begin
    // Restart flow: Clear the playing field, reset the status, restart the timer if necessary
    FGameOver := False;
    FScore := 0;
    FLevel := 0;
    FLinesCleared := 0;
    FPieceDropDelay := PieceDropDelays[0];
    FillChar(FBoard, SizeOf(FBoard), 0); // Clear gaming board
    RedrawBoard;
    UpdateStats;

    // If timer has been stopped, recreate / start
    if Assigned(FTimer) and not FTimer.Started then
    begin
      FTimer := TGorillaTimer.Create;
      FTimer.Interval := 16;
      FTimer.OnTimer := DoOnTick;
      FTimer.Start;
    end;

    SpawnPiece;
    Exit;
  end;

  if FHardDrop then
    Exit;

  FWithGesture := true;
  case EventInfo.GestureID of

    // Piece Movement
    sgiLeft  :
      begin
        FLeftHeld := True;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;

    sgiRight :
      begin
        FRightHeld := True;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;

    // Piece Rotation
    sgiUp :
      begin
        RotatePiece(FCurrentPiece, +1, FBoard);
        RedrawActive;
      end;

    sgiDown :
      begin
        RotatePiece(FCurrentPiece, -1, FBoard);
        RedrawActive;
      end;

    // Dropping
    igiRotate :
      begin
        if (TInteractiveGestureFlag.gfEnd in EventInfo.Flags) then
        begin
          // Hard Drop
          FHardDrop := true;
          FHardDropExtraPoints := true;
        end;
      end;
  end;
end;

procedure TForm1.InitBoard;
var x,y  : Integer;
    cube : TGorillaMeshInstance;
    mat  : TGorillaDefaultMaterialSource;
begin
  for y := 0 to ROWS-1 do
    for x := 0 to COLS-1 do
    begin
      FBoard[y, x] := ckNone;

      cube := FTemplates[ckNone].AddInstanceItem(Format('%d_%d', [X, Y]));
      cube.Position.Point := Point3D(x, y, 0);
      cube.Scale.Point := Point3D(0.95, 0.95, 0.95);
      FCubes[y, x] := cube;
    end;
end;

procedure TForm1.RedrawBoard;
var x,y : Integer;
    mat : TGorillaDefaultMaterialSource;
begin
  for y := 0 to ROWS - 1 do
    for x := 0 to COLS - 1 do
    begin
      if FBoard[y, x] <> ckNone then
      begin
        // If the type of the cube has changed
        if Assigned(FCubes[y, x])
        and (FCubes[y, x].OwnerMesh <> FTemplates[FBoard[y, x]]) then
        begin
          FCubes[y, x].OwnerMesh.DeleteInstance(FCubes[y, x].Index);
          FCubes[y, x] := nil;
        end;

        if not Assigned(FCubes[y, x]) then
        begin
          // If a cube is missing (e.g. after moving), create it again
          FCubes[y, x] := FTemplates[FBoard[y, x]].AddInstanceItem(Format('%d_%d', [X, Y]));
        end;

        FCubes[y, x].Position.Point := Point3D(x, y, 0);
        FCubes[y, x].Scale.Point := Point3D(0.95, 0.95, 0.95);
      end
      else
      begin
        if Assigned(FCubes[y, x]) then
        begin
          if (FCubes[y, x].OwnerMesh <> FTemplates[FBoard[y, x]]) then
          begin
            // Delete the previous cube instance
            FCubes[y, x].OwnerMesh.DeleteInstance(FCubes[y, x].Index);
            FCubes[y, x] := nil;
          end;
        end;

        if not Assigned(FCubes[y, x]) then
        begin
          // Add a new instance for this cube
          FCubes[y, x] := FTemplates[ckNone].AddInstanceItem(Format('%d_%d', [X, Y]));
        end;

        FCubes[y, x].Position.Point := Point3D(x, y, 0);
        FCubes[y, x].Scale.Point := Point3D(0.95, 0.95, 0.95);
      end;
    end;
end;

procedure TForm1.SpawnPiece;
begin
  if FGameOver then Exit;

  FHardDrop := false;
  FHardDropExtraPoints := false;

  // Take the next piece from the preview (the preview was filled from the bag)
  FCurrentPiece.Kind := FNextPieces[0];

  // Push the queue: 1 -> 0, new from bag into slot 1
  FNextPieces[0] := FNextPieces[1];
  FNextPieces[1] := DrawFromBag;

  UpdatePreview;

  // Piece initialization
  FCurrentPiece.Matrix := PieceShapes[FCurrentPiece.Kind];
  FCurrentPiece.Rot := 0;
  FCurrentPiece.X := (COLS div 2) - 2;
  FCurrentPiece.Y := -2;

  if Collides(FCurrentPiece.Matrix, FCurrentPiece.X, FCurrentPiece.Y, FBoard) then
  begin
    HandleGameOver;
    Exit;
  end;

  RedrawActive;
end;

procedure TForm1.FormKeyDown(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  if FGameOver and (Key = vkReturn) then
  begin
    // Restart flow: Clear the playing field, reset the status, restart the timer if necessary
    FGameOver := False;
    FScore := 0;
    FLevel := 0;
    FLinesCleared := 0;
    FPieceDropDelay := PieceDropDelays[0];
    FillChar(FBoard, SizeOf(FBoard), 0);
    RedrawBoard;
    UpdateStats;

    // If timer has been stopped, recreate / start
    if Assigned(FTimer) and not FTimer.Started then
    begin
      FTimer := TGorillaTimer.Create;
      FTimer.Interval := 16;
      FTimer.OnTimer := DoOnTick;
      FTimer.Start;
    end;

    SpawnPiece;
    Exit;
  end;

  if FHardDrop then
    Exit;

  case Key of
    vkLeft :
      begin
        FLeftHeld := True;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;

    vkRight :
      begin
        FRightHeld := True;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;

    vkDown : FDownHeld := True;

    vkUp :
      begin
        RotatePiece(FCurrentPiece, +1, FBoard);
        RedrawActive;
      end;

    vkZ :
      begin
        RotatePiece(FCurrentPiece, -1, FBoard);
        RedrawActive;
      end;

    0,
    vkSpace :
      begin
        FHardDrop := true;
        FHardDropExtraPoints := true;
      end;
  end;
end;

procedure TForm1.FormKeyUp(Sender: TObject; var Key: Word; var KeyChar: Char; Shift: TShiftState);
begin
  case Key of
    vkLeft:
      begin
        FLeftHeld := False;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;
    vkRight:
      begin
        FRightHeld := False;
        FIsInitialMove := False;
        FMoveTimer := 0;
        FMoveIntensity := 1;
      end;
    vkDown: FDownHeld := False;
  end;
end;

function CellsOf(const M: TPieceMatrix): TArray<TPoint>;
var i,j,c: Integer;
begin
  SetLength(Result,4); c := 0;
  for j:=0 to 3 do
    for i:=0 to 3 do
      if M[j,i] then begin Result[c]:=Point(i,j); Inc(c); end;
end;

procedure TForm1.RedrawActive;
var cells: TArray<TPoint>;
    i: Integer;
    p: TPoint;
    col: TAlphaColor;
    mat: TGorillaDefaultMaterialSource;
begin
  cells := CellsOf(FCurrentPiece.Matrix);
  col := PieceColors[FCurrentPiece.Kind];

  for i := 0 to 3 do
  begin
    p := cells[i];
    if FActiveCubes[i] = nil then
      FActiveCubes[i] := Self.FTemplates[FCurrentPiece.Kind].AddInstanceItem('ActiveCube' + IntToStr(i));

    if FActiveCubes[i] <> nil then
    begin
      FActiveCubes[i].Position.Point := Point3D(FCurrentPiece.X + p.X, (FCurrentPiece.Y + p.Y), 0);
    end;
  end;

  RedrawGhost;
end;

procedure TForm1.LockPiece;
var cells: TArray<TPoint>;
    p: TPoint;
    i: Integer;
    WasHardDrop: Boolean;
begin
  // Note whether the lock was initiated by HardDrop
  WasHardDrop := FHardDrop;
  FHardDrop := False;

  cells := CellsOf(FCurrentPiece.Matrix);
  for i:=0 to 3 do
  begin
    p := cells[i];
    if FCurrentPiece.Y + p.Y >= 0 then
      FBoard[FCurrentPiece.Y + p.Y, FCurrentPiece.X + p.X] := FCurrentPiece.Kind;
  end;

  for i := 0 to 3 do
    if Assigned(FActiveCubes[i]) then
    begin
      FActiveCubes[i].OwnerMesh.DeleteInstance(FActiveCubes[i].Index);
      FActiveCubes[i] := nil;
    end;

  for i := 0 to 3 do
    if Assigned(FGhostCubes[i]) then
    begin
      FGhostCubes[i].OwnerMesh.DeleteInstance(FGhostCubes[i].Index);
      FGhostCubes[i] := nil;
    end;

  // Redraw board (so that FCubes exist / are visible)
  RedrawBoard;

  // If it was a hard drop => start the shake animation and execute ClearLines after the animation ends.
  if WasHardDrop then
  begin
    StartShakeBoard;
  end
  else
  begin
    // Normal behavior: check / delete lines immediately
    ClearLines;
  end;
end;

procedure TForm1.Clear;
begin
  System.SetLength(FAnimatedCubes, 0);
  System.SetLength(FShakingCubes, 0);
  System.SetLength(FDroppingCubes, 0);

  for var I := 0 to 1 do
    for var J := 0 to 3 do
      FPreviewCubes[I][J] := nil;

  for var I := 0 to 3 do
    FActiveCubes [I] := nil;

  for var i := 0 to 3 do
    if Assigned(FGhostCubes[i]) then
    begin
      FGhostCubes[i].OwnerMesh.DeleteInstance(FGhostCubes[i].Index);
      FGhostCubes [I] := nil;
    end;
end;

procedure TForm1.ClearLines;
var
  y, x: Integer;
  full: Boolean;
  linesToClear: TArray<Integer>;
begin
  SetLength(linesToClear, 0);

  // Step 1: Find all full rows and save them
  for y := ROWS - 1 downto 0 do
  begin
    full := True;
    for x := 0 to COLS - 1 do
    begin
      if FBoard[y, x] = ckNone then
      begin
        full := False;
        Break;
      end;
    end;

    if full then
    begin
      linesToClear := linesToClear + [y];
    end;
  end;

  if Length(linesToClear) > 0 then
  begin
    // Step 2: Award points and increase levels
    var LScore := 0;
    case Length(linesToClear) of
      1: begin
            LScore := 40 * (FLevel + 1);
            if FHardDropExtraPoints then
              LScore := LScore + 10;
         end;
      2: begin
            LScore := 100 * (FLevel + 1);
            if FHardDropExtraPoints then
              LScore := LScore + 50;
         end;
      3: begin
            LScore := 300 * (FLevel + 1);
            if FHardDropExtraPoints then
              LScore := LScore + 100;
         end;
      4: begin
            LScore := 1200 * (FLevel + 1);
            if FHardDropExtraPoints then
              LScore := LScore + 300;
         end;
    end;

    FScore := FScore + LScore;

    FLinesCleared := FLinesCleared + Length(linesToClear);
    if FLinesCleared div 10 > FLevel then
    begin
      Inc(FLevel);
      if FLevel <= High(PieceDropDelays) then
        FPieceDropDelay := PieceDropDelays[FLevel];
    end;

    // Save the lines to be deleted and start animation
    FRemovedLines := Copy(linesToClear);
    StartLineClearAnimation(linesToClear);
  end
  else
  begin
    // If no lines have been deleted, immediately spawn the next part
    if not FGameOver then
      SpawnPiece;
  end;

  FHardDropExtraPoints := false;
end;

procedure TForm1.RedrawGhost;
var cells: TArray<TPoint>;
    i: Integer;
    p: TPoint;
    GhostPiece: TPiece;
begin
  // Copy the current block
  GhostPiece := FCurrentPiece;

  // Find the lowest position where the block can land
  while not Collides(GhostPiece.Matrix, GhostPiece.X, GhostPiece.Y + 1, FBoard) do
    Inc(GhostPiece.Y);

  cells := CellsOf(GhostPiece.Matrix);

  // Update the position and visibility of the ghost cubes
  for i := 0 to 3 do
  begin
    p := cells[i];

    if FGhostCubes[i] = nil then
      FGhostCubes[i] := FGhostTemplate.AddInstanceItem('Ghost' + IntToStr(i));

    if FGhostCubes[i] <> nil then
    begin
      FGhostCubes[i].Position.Point := Point3D(GhostPiece.X + p.X, GhostPiece.Y + p.Y, 0);
    end;
  end;
end;

procedure TForm1.StartLineClearAnimation(const Lines: TArray<Integer>);
var
  y, x: Integer;
  cube: TGorillaMeshInstance;
  idx: Integer;
begin
  FIsAnimating := True;
  FAnimationTimer := 0;
  FExplosionTriggered := False;

  // Move blocks from the rows to be deleted into the animation array
  SetLength(FAnimatedCubes, Length(Lines) * COLS);
  SetLength(FAnimatedVelocities, Length(Lines) * COLS);
  SetLength(FAnimatedBasePos, Length(Lines) * COLS);
  SetLength(FAnimatedVibrateDirs, Length(Lines) * COLS);
  SetLength(FAnimatedPhases, Length(Lines) * COLS);

  idx := 0;
  for y in Lines do
  begin
    for x := 0 to COLS - 1 do
    begin
      cube := FCubes[y, x];
      if Assigned(cube) and (cube.OwnerMesh <> FTemplates[ckNone]) then
      begin
        // Save base position (for vibration)
        FAnimatedBasePos[idx] := cube.Position.Point;

        // Beginning: no explosion speed, only vibration
        FAnimatedVelocities[idx] := Vector3D(0,0,0);

        // Random vibration direction and phase
        var dir := Vector3D(
          RandomRange(-100, 100) / 100,
          RandomRange(-100, 100) / 100,
          RandomRange(-100, 100) / 100
        );

        // Normalize if not zero
        var len := Sqrt(dir.X * dir.X + dir.Y * dir.Y + dir.Z * dir.Z);
        if len > 0 then
          dir := Vector3D(dir.X / len, dir.Y / len, dir.Z / len)
        else
          dir := Vector3D(0, 1, 0);
        FAnimatedVibrateDirs[idx] := dir;

        FAnimatedPhases[idx] := RandomRange(0, 31415) / 5000; // 0..~6.283 (radians)

        // Delete instance and create a new one with the Electric effect
        var LPrevPos := cube.Position.Point;
        var bs := FBoard[y, x];
        cube.OwnerMesh.DeleteInstance(cube.Index);
        FCubes[y, x] := nil;

        // Transfer reference to the animation array
        FAnimatedCubes[idx] := FTemplatesElectric[bs].AddInstanceItem(
          Format('%d_%d', [X, Y]));
        FAnimatedCubes[idx].Position.Point := LPrevPos;

        Inc(idx);
      end;

      // Remove reference in the grid – the object now belongs to the animation
      FCubes[y,x] := nil;
    end;
  end;

  SetLength(FAnimatedCubes, idx);
  SetLength(FAnimatedVelocities, idx);
  SetLength(FAnimatedBasePos, idx);
  SetLength(FAnimatedVibrateDirs, idx);
  SetLength(FAnimatedPhases, idx);
end;

procedure TForm1.HandleGameOver;
begin
  if FGameOver then Exit;

  for var s := 0 to 1 do
    for var c := 0 to 3 do
      if Assigned(FPreviewCubes[s,c]) then
        FPreviewCubes[s,c].Visible := False;

  // Queue UI-calls in main thread
  TThread.Queue(nil,
    procedure
    var i: Integer;
    begin
      for i := 0 to 3 do
        if Assigned(FActiveCubes[i]) then
          try
            FActiveCubes[i].OwnerMesh.DeleteInstance(FActiveCubes[i].Index);
            FActiveCubes[i] := nil;
          except
          end;

      // Stop the timer so that no more DoOnTick calls come
      if Assigned(FTimer) and FTimer.Started then
        FTimer.Terminate;

      FinalScoreLabel.Text := IntToStr(FScore);
      Image4.Visible := true;

      Clear;
    end);
end;

procedure TForm1.UpdatePreview;
var
  slot, k: Integer;
  cells: TArray<TPoint>;
  p: TPoint;
  baseX, baseY: Single;
  col: TAlphaColor;
  mat: TGorillaDefaultMaterialSource;
begin
  // Place preview slots to the right of the field (outside the right border)
  // Slot 0 above, Slot 1 below
  for slot := 0 to 1 do
  begin
    // Base position for this slot (adjust if necessary)
    baseX := COLS + 3 + (slot * 0); // same X position; Y differs further down
    baseY := 18 + slot * 2; // Distance between slot 0 and 1

    // Calculate cell offsets for the piece (use the PieceMatrix)
    cells := CellsOf(PieceShapes[FNextPieces[slot]]);

    col := PieceColors[FNextPieces[slot]];
    for k := 0 to 3 do
    begin
      p := cells[k];
      if (FPreviewCubes[slot,k] = nil) then
        Continue;

      // Positioning: we center each 4x4 matrix within a small preview box
      // Move X and Y so that it sits comfortably next to the grid
      FPreviewCubes[slot,k].Visible := True;
      FPreviewCubes[slot,k].Position.Point :=
        Point3D(baseX + (p.X * 0.5 - 1.5), baseY + (p.Y * 0.5 - 1.0), 0);

      // Material color / Emissive as with the normal block (slightly less intense possible)
      mat := TGorillaDefaultMaterialSource(FPreviewCubes[slot,k].MaterialSource);
      if not Assigned(mat) then
      begin
        mat := TGorillaDefaultMaterialSource.Create(FGorilla);
        mat.ShadingModel := TGorillaShadingModel.smBlinnPhong;
        mat.UseLighting := true;
        mat.UseSpecular := true;
        mat.Parent := FGorilla;
        FPreviewCubes[slot,k].MaterialSource := mat;
      end;
    end;
  end;
end;

procedure TForm1.ShuffleBag;
var
  i, j: Integer;
  tmp: TCellKind;
begin
  // Fisher-Yates shuffle for 7 elements
  for i := 6 downto 1 do
  begin
    j := Random(i + 1); // 0..i
    tmp := FBag[i];
    FBag[i] := FBag[j];
    FBag[j] := tmp;
  end;
end;

procedure TForm1.RefillBag;
var
  i: Integer;
begin
  // Fill Bag with the 7 Tetromino types (ckI..ckL)
  for i := 0 to 6 do
    FBag[i] := TCellKind(Ord(ckI) + i);

  // Mix it!
  ShuffleBag;
  FBagIndex := 0;
end;

function TForm1.DrawFromBag: TCellKind;
begin
  // If the bag is empty (Index > 6), refill it
  if FBagIndex > 6 then
    RefillBag;

  Result := FBag[FBagIndex];
  Inc(FBagIndex);

  // If we just removed the last element,
  // immediately prepare a new bag (optional)
  if FBagIndex > 6 then
    RefillBag;
end;

procedure TForm1.StartShakeBoard;
var
  y, x, idx: Integer;
  cube: TGorillaMeshInstance;
  amp, baseFreq: TVector3D;
begin
  // Parameters: Duration and number of complete oscillations (back+forth = 1 oscillation)
  FShakeDuration := 0.5;      // Total duration in seconds (longer to allow multiple oscillations to be visible)
  FShakeOscillations := 4;    // Number of full back/forth oscillations
  FShakeTimer := 0;
  FIsShaking := True;

  // Collect all visible/discarded dice into an array
  SetLength(FShakingCubes, 0);
  for y := 0 to ROWS - 1 do
    for x := 0 to COLS - 1 do
      if (FBoard[y, x] <> ckNone) and Assigned(FCubes[y, x]) then
      begin
        idx := Length(FShakingCubes);
        SetLength(FShakingCubes, idx + 1);
        FShakingCubes[idx] := FCubes[y,x];
      end;

  // Reserve helper arrays
  SetLength(FShakeOrigPos, Length(FShakingCubes));
  SetLength(FShakeAmplitudes, Length(FShakingCubes));
  SetLength(FShakeBaseFreqs, Length(FShakingCubes));

  // Fill start values: origin, amplitude, base frequency
  for idx := 0 to High(FShakingCubes) do
  begin
    cube := FShakingCubes[idx];
    if Assigned(cube) then
    begin
      // Store the original position
      FShakeOrigPos[idx] := cube.Position.Point;

      // Amplitudes: somewhat random, possibly scaled up by the user
      amp := Vector3D(
        (RandomRange(8, 36) / 100.0),  // X amplitude (0.08..0.36)
        (RandomRange(4, 18) / 100.0),  // Y amplitude
        (RandomRange(0, 12) / 100.0)   // Z amplitude
      );

      // Optional: multiply the values ​​by 3 here if you want it extra strong:
      // amp := Vector3D(amp.X * 3, amp.Y * 3, amp.Z * 3);
      FShakeAmplitudes[idx] := amp;

      // Base frequency in Hz (used together with FShakeOscillations)
      // We choose moderate bases, variation per cube
      baseFreq := Vector3D(
        RandomRange(8, 14) / 10.0, // 0.8..1.4
        RandomRange(8, 14) / 10.0,
        RandomRange(8, 14) / 10.0
      );

      // If you've already multiplied by 3 everywhere, this results in stronger, faster movement.
      // baseFreq := baseFreq * 3; // if desired (you had x3)
      FShakeBaseFreqs[idx] := baseFreq;
    end;
  end;

  // Optional camera variation per-Shake: slight random components
  if FCameraShakeEnabled and Assigned(FCamera) then
  begin
    // Remember the original position (again if it has changed between spawns)
    FCameraOrigPos := FCamera.Position.Point;

    // Optional: slight random scaling of the camera amplitude (variation)
    FCameraShakeAmplitude := Vector3D(
      FCameraShakeAmplitude.X * (0.9 + RandomRange(0,20)/100),
      FCameraShakeAmplitude.Y * (0.9 + RandomRange(0,20)/100),
      FCameraShakeAmplitude.Z
    );

    // Optional: Vary base frequencies slightly
    FCameraShakeBaseFreq := Vector3D(
      FCameraShakeBaseFreq.X * (0.9 + RandomRange(0,20)/100),
      FCameraShakeBaseFreq.Y * (0.9 + RandomRange(0,20)/100),
      FCameraShakeBaseFreq.Z
    );
  end;
end;

procedure TForm1.StartDropAnimation;
var
  x, y, idx, dropCount: Integer;
  cube: TGorillaMeshInstance;
  startPos, endPos: TVector3D;
  removedFlag: array[0..ROWS-1] of Boolean;
begin
  if Length(FRemovedLines) = 0 then Exit;

  // 1) Mark removed lines
  FillChar(removedFlag, SizeOf(removedFlag), 0);
  for y in FRemovedLines do
    if (y >= 0) and (y < ROWS) then
      removedFlag[y] := True;

  // 2) Deletes the lines immediately in board
  for y in FRemovedLines do
    for x := 0 to COLS-1 do
    begin
      FBoard[y, x] := ckNone;
      if Assigned(FCubes[y, x]) then
        FCubes[y, x] := nil;
    end;

  SetLength(FDroppingCubes, 0);
  SetLength(FDropStartPos, 0);
  SetLength(FDropEndPos, 0);
  SetLength(FDropDelay, 0);

  // 3) Drop only for dice above deleted lines
  for x := 0 to COLS - 1 do
  begin
    dropCount := 0;
    for y := ROWS - 1 downto 0 do
    begin
      if removedFlag[y] then
      begin
        Inc(dropCount);
        Continue;
      end;

      if FBoard[y, x] <> ckNone then
      begin
        cube := FCubes[y, x];
        if Assigned(cube) and (dropCount > 0) then
        begin
          startPos := cube.Position.Point;
          endPos := Point3D(startPos.X, startPos.Y + dropCount, startPos.Z);

          idx := Length(FDroppingCubes);
          SetLength(FDroppingCubes, idx + 1);
          SetLength(FDropStartPos, idx + 1);
          SetLength(FDropEndPos, idx + 1);
          SetLength(FDropDelay, idx + 1);

          FDroppingCubes[idx] := cube;
          FDropStartPos[idx] := startPos;
          FDropEndPos[idx] := endPos;
          FDropDelay[idx] := Random * 0.18;

          // Update board immediately
          FBoard[y + dropCount, x] := FBoard[y, x];
          FCubes[y + dropCount, x] := cube;

          FBoard[y, x] := ckNone;
          FCubes[y, x] := nil;
        end;
      end;
    end;
  end;

  if Length(FDroppingCubes) > 0 then
  begin
    FDropTimer := 0;
    FDropDuration := 0.35;
    FIsDropping := True;
  end;

  SetLength(FRemovedLines, 0);
end;

end.
