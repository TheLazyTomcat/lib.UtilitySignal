{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  UtilitySignal

    Small library designed to ease setup of real-time signal handlers in Linux.
    It was designed primarily for use with posix timers (and possibly message
    queues), but can be, of course, used for other purposes too.

    I have decided to write it for two main reasons - one is to provide some
    siplified interface allowing for multiple handlers of single signal,
    the second is to limit number of used signals, of which count is very
    limited (30 or 32 per process in Linux), by allowing multiple users
    to use one signal allocated here.

    It was designed to be close in use to UtilityWindow library - so, to use
    it, create an instance of TUitilitySignal and assign events or callbacks to
    its OnSignal multi-event object. Also, to properly process the incoming
    signals (see implementation notes further) and pass them to assigned
    events/callbacks, you need to repeatedly call method ProcessSignal or
    ProcessSignals. Next, when setting-up the signal-producing system (eg. the
    timer), pass the instance as pointer signal value.

    Few words on implementation...

      At unit initialization, this library selects and allocates one unused
      real-time signal and then installs an action routine that receives all
      incoming invocations of that signal.

        Note that this signal can be different every time the process is run.
        It can also differ between processes even if they are started from the
        same executable. Which means, among others, that this library cannot be
        used for interprocess communication, be aware of that!

        If this library is used multiple times within the same process (eg.
        when loaded with a dynamic library), this signal will be different for
        each instance. Because the number of available signals is limited, you
        should refrain from using this unit in a library or make sure one
        instance is shared across the entire process.

      Assigned action routine, when called by the system, stores the incoming
      signal into a buffer and immediately exits - the signal is not propagated
      directly to handlers because that way the async signal safety cannot be
      guaranteed (see Linux manual, signal-safety(7)).

      Buffer of incoming signals has large but invariant size (it cannot be
      enlarged), therefore there might arise situation where it becomes full -
      in this case oldest stored signals are dropped to make space for new
      ones. If symbol FailOnSignalDrop is defined, then this will produce an
      exception, otherwise it is silent.

      To pass stored signals from these buffers to desired handlers (events,
      callbacks), you need to call routines processing signals (for example
      TUitilitySignal.ProcessSignals or function ProcessOrphanSignals).

    Make sure you understand how signals work before using this library, so
    reading the linux manual (signal(7)) is strongly recommended.

  Version 2.1 (2025-02-28)

  Last change 2025-02-28

  ©2024-2025 František Milt

  Contacts:
    František Milt: frantisek.milt@gmail.com

  Support:
    If you find this code useful, please consider supporting its author(s) by
    making a small donation using the following link(s):

      https://www.paypal.me/FMilt

  Changelog:
    For detailed changelog and history please refer to this git repository:

      github.com/TheLazyTomcat/Lib.UtilitySignal

  Dependencies:
    AuxClasses        - github.com/TheLazyTomcat/Lib.AuxClasses
  * AuxExceptions     - github.com/TheLazyTomcat/Lib.AuxExceptions
    AuxTypes          - github.com/TheLazyTomcat/Lib.AuxTypes
    InterlockedOps    - github.com/TheLazyTomcat/Lib.InterlockedOps
    MulticastEvent    - github.com/TheLazyTomcat/Lib.MulticastEvent
  * ProcessGlobalVars - github.com/TheLazyTomcat/Lib.ProcessGlobalVars
    SequentialVectors - github.com/TheLazyTomcat/Lib.SequentialVectors

  Library AuxExceptions is required only when rebasing local exception classes
  (see symbol UtilitySignal_UseAuxExceptions for details).

  Library ProcessGlobalVars is required only when symbol ModuleShared is
  defined.

  Library AuxExceptions might also be required as an indirect dependency.

  Indirect dependencies:
    Adler32             - github.com/TheLazyTomcat/Lib.Adler32
    AuxMath             - github.com/TheLazyTomcat/Lib.AuxMath
    BinaryStreamingLite - github.com/TheLazyTomcat/Lib.BinaryStreamingLite
    HashBase            - github.com/TheLazyTomcat/Lib.HashBase
    SimpleCPUID         - github.com/TheLazyTomcat/Lib.SimpleCPUID
    StaticMemoryStream  - github.com/TheLazyTomcat/Lib.StaticMemoryStream
    StrRect             - github.com/TheLazyTomcat/Lib.StrRect
    UInt64Utils         - github.com/TheLazyTomcat/Lib.UInt64Utils
    WinFileInfo         - github.com/TheLazyTomcat/Lib.WinFileInfo

===============================================================================}
unit UtilitySignal;
{
  UtilitySignal_UseAuxExceptions

  If you want library-specific exceptions to be based on more advanced classes
  provided by AuxExceptions library instead of basic Exception class, and don't
  want to or cannot change code in this unit, you can define global symbol
  UtilitySignal_UseAuxExceptions to achieve this.
}
{$IF Defined(UtilitySignal_UseAuxExceptions)}
  {$DEFINE UseAuxExceptions}
{$IFEND}

//------------------------------------------------------------------------------

{$IF Defined(LINUX) and Defined(FPC)}
  {$DEFINE Linux}
{$ELSE}
  {$MESSAGE FATAL 'Unsupported operating system.'}
{$IFEND}

{$IFDEF FPC}
  {$MODE ObjFPC}
  {$MODESWITCH DuplicateLocals+}
  {$MODESWITCH ClassicProcVars+}
  {$DEFINE FPC_DisableWarns}
  {$MACRO ON}
{$ENDIF}
{$H+}

//------------------------------------------------------------------------------
{
  LargeBuffers
  HugeBuffers
  MassiveBuffers

  These three symbols control size of buffers and queues used internally by
  this library. Larger buffers/queues can prevent signal loss/drop, but
  they significantly increase memory consumption and may also degrade
  performance.

  LargeBuffer muptiplies default buffer size / queue length by 16, HugeBuffers
  by 128 and MassiveBuffers multiplies buffer sizes by 1024 and sets queues
  to unlimited length (technical limits are still in effect of course).

  If more than one of these three symbols are defined, then only the "largest"
  is observed.

  None is defined by default.

  To enable/define these symbols in a project without changing this library,
  define project-wide symbol UtilitySignal_LargeBuffers_On,
  UtilitySignal_HugeBuffers_On or UtilitySignal_MassiveBuffers_On.
}
{$UNDEF LargeBuffers}
{$IFDEF UtilitySignal_LargeBuffers_On}
  {$DEFINE LargeBuffers}
{$ENDIF}
{$UNDEF HugeBuffers}
{$IFDEF UtilitySignal_HugeBuffers_On}
  {$DEFINE HugeBuffers}
{$ENDIF}
{$UNDEF MassiveBuffers}
{$IFDEF UtilitySignal_MassiveBuffers_On}
  {$DEFINE MassiveBuffers}
{$ENDIF}

{
  FailOnSignalDrop

  When this symbol is defined and signal is dropped/lost due to full buffer or
  limited-length queue, an exception of class EUSSignalLost is raised. When not
  defined, nothing happens in that situation as signals are dropped silently.

  Not defined by default.

  To enable/define this symbol in a project without changing this library,
  define project-wide symbol UtilitySignal_FailOnSignalDrop_On.
}
{$UNDEF FailOnSignalDrop}
{$IFDEF UtilitySignal_FailOnSignalDrop_On}
  {$DEFINE FailOnSignalDrop}
{$ENDIF}

{
  ModuleShared

  When defined, then this library will share global state with instances of
  itself in other modules loaded within current process (note that it will
  cooperate only with instances that were also compiled with this symbol).
  If used correctly, this can prevent unnecessary allocation of multiple
  signals for the same purpose in differing modules.

  If not defined, then this library will operate only within a single module
  into which it is compiled.

  Defined by default.

  To disable/undefine this symbol in a project without changing this library,
  define project-wide symbol UtilitySignal_ModuleShared_Off.
}
{$DEFINE ModuleShared}
{$IFDEF UtilitySignal_ModuleShared_Off}
  {$UNDEF ModuleShared}
{$ENDIF}

interface

uses
  SysUtils, BaseUnix, SyncObjs,
  SequentialVectors, AuxClasses, MulticastEvent
  {$IFDEF UseAuxExceptions}, AuxExceptions{$ENDIF};

{===============================================================================
    Library-specific exceptions
===============================================================================}
type
  EUSException = class({$IFDEF UseAuxExceptions}EAEGeneralException{$ELSE}Exception{$ENDIF});

  EUSSignalSetupError = class(EUSException);
  EUSSignalLost       = class(EUSException);

  EUSInvalidValue = class(EUSException);

  EUSGlobalStateOpenError    = class(EUSException);
  EUSGlobalStateCloseError   = class(EUSException);
  EUSGlobalStateMutexError   = class(EUSException);
  EUSGlobalStateModListError = class(EUSException);

{===============================================================================
--------------------------------------------------------------------------------
                                Utility functions
--------------------------------------------------------------------------------
===============================================================================}
type
  TUSSignalValue = record
    case Integer of
      0: (IntValue: Integer);
      1: (PtrValue: Pointer);
  end;

{===============================================================================
    Utility functions - declaration
===============================================================================}
{
  IsPrimaryModule

  When symbol ModuleShared is defined, then this function indicates whether
  module into which it is compiled is a primary module - that is, it has signal
  action handler installed and is responsible for incoming signals processing.

  If ModuleShared is not defined, then this function always returns True.

    NOTE - non-primary module can become primary if current primary module is
           unloaded and selects this module as new primary. Therefore do not
           assume that whatever this function returns is invariant.
}
Function IsPrimaryModule: Boolean;

{
  AllocatedSignal

  Returns signal ID (number) that was allocated for use by this library.
}
Function AllocatedSignal: cint;

{
  GetCurrentProcessID

  Returns ID of the calling process. This can be used when sending a signal
  (see functions SendSignal further down).
}
Function GetCurrentProcessID: pid_t;

//------------------------------------------------------------------------------
{
  SendSignalTo

  Sends selected signal to a given process with given value.

  When the sending succeeds, true is returned and output parameter Error is set
  to 0. When it fails, false is returned and Error contains Linux error code
  that describes reason of failure.

  Note that sending signals is subject to privilege checks, so it might not be
  possible, depending on what privileges the sending process have.

  The signal will arrive with code set to SI_QUEUE.

    WARNING - signals are quite deep subject, so do not use provided functions
              without considering what are you about to do. Always read your
              operating system's manual.
}
Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: TUSSignalValue; out Error: Integer): Boolean; overload;
Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Integer; out Error: Integer): Boolean; overload;
Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Pointer; out Error: Integer): Boolean; overload;

Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: TUSSignalValue): Boolean; overload;
Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Integer): Boolean; overload;
Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Pointer): Boolean; overload;

{
  SendSignal

  These functions are sending signal back to the calling process (but not
  necessarily the calling thread!) using the signal allocated for this library.
}
Function SendSignal(Value: TUSSignalValue; out Error: Integer): Boolean; overload;
Function SendSignal(Value: Integer; out Error: Integer): Boolean; overload;
Function SendSignal(Value: Pointer; out Error: Integer): Boolean; overload;

Function SendSignal(Value: TUSSignalValue): Boolean; overload;
Function SendSignal(Value: Integer): Boolean; overload;
Function SendSignal(Value: Pointer): Boolean; overload;

{===============================================================================
--------------------------------------------------------------------------------
                               TUSSignalCodeQueue
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUSSignalCodeQueue - class declaration
===============================================================================}
type
  // used only internally
  TUSSignalCodeQueue = class(TIntegerQueueVector)
  protected
  {$IFDEF FailOnSignalDrop}
    procedure ItemDrop(Item: Pointer); override;
  {$ENDIF}
  end;

{===============================================================================
--------------------------------------------------------------------------------
                           TUSMulticastSignalCodeEvent
--------------------------------------------------------------------------------
===============================================================================}
type
  TUSSignalCodeCallback = procedure(Sender: TObject; Code: Integer; var BreakProcessing: Boolean);
  TUSSignalCodeEvent = procedure(Sender: TObject; Code: Integer; var BreakProcessing: Boolean) of object;

{===============================================================================
    TUSMulticastSignalCodeEvent - class declaration
===============================================================================}
type
  // used only internally
  TUSMulticastSignalCodeEvent = class(TMulticastEvent)
  public
    Function IndexOf(const Handler: TUSSignalCodeCallback): Integer; reintroduce; overload;
    Function IndexOf(const Handler: TUSSignalCodeEvent): Integer; reintroduce; overload;
    Function Find(const Handler: TUSSignalCodeCallback; out Index: Integer): Boolean; reintroduce; overload;
    Function Find(const Handler: TUSSignalCodeEvent; out Index: Integer): Boolean; reintroduce; overload;
    Function Add(Handler: TUSSignalCodeCallback): Integer; reintroduce; overload;
    Function Add(Handler: TUSSignalCodeEvent): Integer; reintroduce; overload;
    Function Remove(const Handler: TUSSignalCodeCallback): Integer; reintroduce; overload;
    Function Remove(const Handler: TUSSignalCodeEvent): Integer; reintroduce; overload;
    procedure Call(Sender: TObject; Code: Integer); reintroduce;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                 TUtilitySignal
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUtilitySignal - class declaration
===============================================================================}
{
  TUtilitySignal

  Instances of this class are a primary mean of receiving signals.

    WARNING - public interface of this class is not fully thread safe. With
              one exception (see property ObserveThread), you should create,
              destroy and use its methods and properties only within a single
              thread.

  Internal queue storing incoming signals before these are passed to assigned
  events/callbacks has limited size (unless symbol MassiveBuffers is defined).
  This means there is a possibility that some signals may be lost when this
  queue becomes full.
  This might produce an exception if symbol FailOnSignalDrop is defined, or
  it might go completely silent when it is not defined. Anyway, you should be
  aware of this limitation.
}
type
  TUtilitySignal = class(TCustomObject)
  protected
    fRegisteredOnIdle:  Boolean;
    fThreadLock:        TCriticalSection;
    fReceivedSignals:   TUSSignalCodeQueue;
    fCreatorThread:     pid_t;
    fObserveThread:     Boolean;
    fCoalesceSignals:   Boolean;
    fOnSignal:          TUSMulticastSignalCodeEvent;
    Function GetCoalesceSignals: Boolean; virtual;
    procedure SetCoalesceSignals(Value: Boolean); virtual;
    procedure Initialize; virtual;
    procedure Finalize; virtual;
    procedure ThreadLock; virtual;
    procedure ThreadUnlock; virtual;
    procedure AddSignal(Code: Integer); virtual;
    Function CheckThread: Boolean; virtual;
    procedure OnAppIdleHandler(Sender: TObject; var Done: Boolean); virtual;
  public
    // Signal returns the same value as standalone function AllocatedSignal
    class Function Signal: Integer; virtual;
  {
    Create

    When argument RegisterForOnIdle is set to true, then method
    RegisterForOnIdle is called within the contructor, otherwise it is not.
  }
    constructor Create(CanRegisterForOnIdle: Boolean = True);
    destructor Destroy; override;
  {
    RegisterForOnIdle

    When this library is compiled in program with LCL, both constructor and
    this method are executed in the context of main thread, then a handler
    calling method ProcessSignals is assigned to application's OnIdle event
    and this method returns true. Otherwise it returns false and no hadler
    is assigned.

    UnregisterFromOnIdle

    Tries to unregister handler from application's OnIdle event (only in
    programs compiled with LCL).
  }
    Function RegisterForOnIdle: Boolean; virtual;
    procedure UnregisterFromOnIdle; virtual;
  {
    ProcessSignal
    ProcessSignals

    Processes all incoming signals (copies them from incoming buffer to their
    respective instances of TUtilitySignal) and then passes all signals meant
    for this instance to events/callbacks assigned to OnSignal multi-event.

    They are processed in the order they have arrived.

    ProcessSignal passes only one signal whereas ProcessSignals passes all
    received signals.

      WARNING - the entire class is NOT externally thread safe. Although it is
                possible to call ProcessSignal(s) from different thread than
                the one that created the object (when ObserveThread is set to
                false), you cannot safely call public methods from multiple
                concurrent threads.
  }
    procedure ProcessSignal; virtual;
    procedure ProcessSignals; virtual;
  {
    RegisteredForAppOnIdle

    True when handler calling ProcessSignals is assigned to appplication's
    OnIdle event, false otherwise.
  }
    property RegisteredForAppOnIdle: Boolean read fRegisteredOnIdle;
  {
    CreatorThread

    ID if thread that created the instance.
  }
    property CreatorThread: pid_t read fCreatorThread;
  {
    ObserveThread

    If ObserveThread is True, then thread calling ProcessSignal(s) must
    be the same as is indicated by CreatorThread (ie. thread that created
    current instance), otherwise nothing happens and these methods exit
    without invoking any event or callback.
    When false, any thread can call mentioned methods - though this is not
    recommended.

      NOTE - default value is True!
  }
    property ObserveThread: Boolean read fObserveThread write fObserveThread;
  {
    CoalesceSignals

    If this is set to false (default), then each signal is processed separately
    (one signal, one call to assigned events/callbacks).

    When set to true, then signals with equal codes are combined into single
    signal, and irrespective of their number, only one invocation of events
    is called with respective code.
  }
    property CoalesceSignals: Boolean read GetCoalesceSignals write SetCoalesceSignals;
    property OnSignal: TUSMulticastSignalCodeEvent read fOnSignal;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                                 Orphan signals
--------------------------------------------------------------------------------
===============================================================================}
{
  Orphan signals are those signals that could not be delivered to any
  TUtilitySignal instance.

  The signals are internally buffered, to pass them to registered events/
  callbacks, call ProcessOrphanSignal(s).
  This internal buffer has limited size (unless symbol MassiveBuffers is
  defined) - if it becomes full, the oldest undelivered signals are dropped
  to make room for new ones. Note that dropping of old signal will raise an
  exception if symbol FailOnSignalDrop is defined, otherwise it is silent.
}
type
  TUSSignalInfo = record
    Signal: Integer;  // this will always be the same (AllocatedSignal)
    Code:   Integer;
    Value:  TUSSignalValue;
  end;

type
  TUSSignalCallback = procedure(Sender: TObject; Data: TUSSignalInfo; var BreakProcessing: Boolean);
  TUSSignalEvent = procedure(Sender: TObject; Data: TUSSignalInfo; var BreakProcessing: Boolean) of object;

//------------------------------------------------------------------------------

procedure RegisterForOrphanSignals(Callback: TUSSignalCallback);
procedure RegisterForOrphanSignals(Event: TUSSignalEvent);

procedure UnregisterFromOrphanSignals(Callback: TUSSignalCallback);
procedure UnregisterFromOrphanSignals(Event: TUSSignalEvent);

//------------------------------------------------------------------------------

procedure ProcessOrphanSignal;
procedure ProcessOrphanSignals;

implementation

uses
  UnixType, SysCall, Classes, {$IFDEF LCL}Forms,{$ENDIF}
  AuxTypes, InterlockedOps{$IFDEF ModuleShared}, ProcessGlobalVars{$ENDIF};

{$LINKLIB C}
{$LINKLIB PTHREAD}

{$IFDEF FPC_DisableWarns}
  {$DEFINE FPCDWM}
  {$DEFINE W4055:={$WARN 4055 OFF}} // Conversion between ordinals and pointers is not portable
  {$DEFINE W5024:={$WARN 5024 OFF}} // Parameter "$1" not used
{$ENDIF}

{===============================================================================
--------------------------------------------------------------------------------
                                Library internals
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Library internals - system stuff
===============================================================================}

Function getpid: pid_t; cdecl; external;

Function errno_ptr: pcint; cdecl; external name '__errno_location';

//------------------------------------------------------------------------------

Function gettid: pid_t;
begin
Result := do_syscall(syscall_nr_gettid);
end;

//==============================================================================
type
  sighandlerfce_t = procedure(signo: cint); cdecl;
  sigactionfce_t =  procedure(signo: cint; siginfo: psiginfo; context: Pointer); cdecl;

  sigset_t = array[0..Pred(1024 div (8 * SizeOf(culong)))] of culong;
  psigset_t = ^sigset_t;

  sigaction_t = record
    handler: record
      case Integer of
        0: (sa_handler:   sighandlerfce_t);
        1: (sa_sigaction: sigactionfce_t);
    end;
    sa_mask:      sigset_t;
    sa_flags:     cint;
    sa_restorer:  Pointer;
  end;
  psigaction_t = ^sigaction_t;

  sigval_t = record
    case Integer of
      0:  (sigval_int: cint);   // Integer value
      1:  (sigval_ptr: Pointer) // Pointer value
  end;

//------------------------------------------------------------------------------

Function allocate_rtsig(high: cint): cint; cdecl; external name '__libc_allocate_rtsig';

Function sigemptyset(_set: psigset_t): cint; cdecl; external;
Function sigaddset(_set: psigset_t; signum: cint): cint; cdecl; external;

Function pthread_sigmask(how: cint; newset,oldset: psigset_t): cint; cdecl; external;

Function pthread_equal(t1: pthread_t; t2: pthread_t): cint; cdecl; external;

Function sigaction(signum: cint; act: psigaction_t; oact: psigaction_t): cint; cdecl; external;
Function sigqueue(pid: pid_t; sig: cint; value: sigval_t): cint; cdecl; external;

//------------------------------------------------------------------------------
{$IFDEF ModuleShared}
const
  PTHREAD_MUTEX_RECURSIVE = 1;
  PTHREAD_MUTEX_ROBUST    = 1;

type
  pthread_mutexattr_p = ^pthread_mutexattr_t;
  pthread_mutex_p = ^pthread_mutex_t;

//------------------------------------------------------------------------------

Function pthread_mutexattr_init(attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutexattr_destroy(attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutexattr_settype(attr: pthread_mutexattr_p; _type: cint): cint; cdecl; external;
Function pthread_mutexattr_setrobust(attr: pthread_mutexattr_p; robustness: cint): cint; cdecl; external;

Function pthread_mutex_init(mutex: pthread_mutex_p; attr: pthread_mutexattr_p): cint; cdecl; external;
Function pthread_mutex_destroy(mutex: pthread_mutex_p): cint; cdecl; external;

Function pthread_mutex_trylock(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_lock(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_unlock(mutex: pthread_mutex_p): cint; cdecl; external;
Function pthread_mutex_consistent(mutex: pthread_mutex_p): cint; cdecl; external;

//------------------------------------------------------------------------------
{$ENDIF}
threadvar
  ThrErrorCode: cInt;

Function PThrResChk(RetVal: cInt): Boolean;
begin
Result := RetVal = 0;
If Result then
  ThrErrorCode := 0
else
  ThrErrorCode := RetVal;
end;

{===============================================================================
    Library internals - implementation constants, types and variables
===============================================================================}
const
{$IF Defined(MassiveBuffers)}
  US_SZCOEF_BUFFER = 1024;
  US_SZCOEF_QUEUE  = -1;  // unlimited
{$ELSEIF Defined(HugeBuffers)}
  US_SZCOEF_BUFFER = 128;
  US_SZCOEF_QUEUE  = 128;
{$ELSEIF Defined(LargeBuffers)}
  US_SZCOEF_BUFFER = 16;
  US_SZCOEF_QUEUE  = 16;
{$ELSE}
  US_SZCOEF_BUFFER = 1;
  US_SZCOEF_QUEUE  = 1;
{$IFEND}

//------------------------------------------------------------------------------
type
  TUSSignalBuffer = record
    Head:     record
      Count:      Integer;
      First:      Integer;
      DropCount:  Integer;
      TakenCount: Integer;
    end;
    Signals:  array[0..Pred(US_SZCOEF_BUFFER * 1024)] of record
      Signal: cint;
      Code:   cint;
      Data:   Pointer;
      Taken:  Boolean;
    end;
  end;
  PUSSignalBuffer = ^TUSSignalBuffer;

//------------------------------------------------------------------------------
var
  // main global variable
  GVAR_ModuleState: record
    Signal:         cint;
    SignalSet:      sigset_t;
    SignalBuffers:  record
      Lock:           Integer;
      Primary:        PUSSignalBuffer;
      Secondary:      PUSSignalBuffer;
    end;
    ProcessingLock: TCriticalSection;
    Dispatcher:     TObject;  // TUSSignalDispatcher
  {$IFDEF ModuleShared}
    GlobalInfo:     record
      IsPrimary:    Boolean;
      HeadVariable: TPGVVariable;
    end;
  {$ENDIF}
  end;

//------------------------------------------------------------------------------
const
  US_SIGRECVLOCK_UNLOCKED = 0;
  US_SIGRECVLOCK_LOCKED   = 1;


{===============================================================================
--------------------------------------------------------------------------------
                                 TUSSignalQueue
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUSSignalQueue - class declaration
===============================================================================}
type
  TUSSignalQueue = class(TSequentialVector)
  protected
    Function GetItem(Index: Integer): TUSSignalInfo; reintroduce;
    procedure SetItem(Index: Integer; NewValue: TUSSignalInfo); reintroduce;
  {$IFDEF FailOnSignalDrop}
    procedure ItemDrop(Item: Pointer); override;
  {$ENDIF}
    procedure ItemAssign(SrcItem,DstItem: Pointer); override;
    Function ItemCompare(Item1,Item2: Pointer): Integer; override;
    Function ItemEquals(Item1,Item2: Pointer): Boolean; override;
  public
    constructor Create(MaxCount: Integer = -1);
    Function IndexOf(Item: TUSSignalInfo): Integer; reintroduce;
    Function Find(Item: TUSSignalInfo; out Index: Integer): Boolean; reintroduce;
    procedure Push(Item: TUSSignalInfo); reintroduce;
    Function Peek: TUSSignalInfo; reintroduce;
    Function Pop: TUSSignalInfo; reintroduce;
    Function Pick(Index: Integer): TUSSignalInfo; reintroduce;
    property Items[Index: Integer]: TUSSignalInfo read GetItem write SetItem;
  end;

{===============================================================================
    TUSSignalQueue - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TUSSignalQueue - protected methods
-------------------------------------------------------------------------------}

Function TUSSignalQueue.GetItem(Index: Integer): TUSSignalInfo;
begin
inherited GetItem(Index,@Result);
end;

//------------------------------------------------------------------------------

procedure TUSSignalQueue.SetItem(Index: Integer; NewValue: TUSSignalInfo);
begin
inherited SetItem(Index,@NewValue);
end;

//------------------------------------------------------------------------------
{$IFDEF FailOnSignalDrop}
procedure TUSSignalQueue.ItemDrop(Item: Pointer);
begin
raise EUSSignalLost.CreateFmt('TUSSignalQueue.ItemDrop: Dropping queued signal (%d, %d, %p).',
  [TUSSignalInfo(Item^).Signal,TUSSignalInfo(Item^).Code,TUSSignalInfo(Item^).Value.PtrValue]);
end;

//------------------------------------------------------------------------------
{$ENDIF}

procedure TUSSignalQueue.ItemAssign(SrcItem,DstItem: Pointer);
begin
TUSSignalInfo(DstItem^) := TUSSignalInfo(SrcItem^);
end;

//------------------------------------------------------------------------------

Function TUSSignalQueue.ItemCompare(Item1,Item2: Pointer): Integer;
begin
If TUSSignalInfo(Item1^).Signal > TUSSignalInfo(Item2^).Signal then
  Result := +1
else If TUSSignalInfo(Item1^).Signal < TUSSignalInfo(Item2^).Signal then
  Result := -1
else
  begin
    If TUSSignalInfo(Item1^).Code > TUSSignalInfo(Item2^).Code then
      Result := +1
    else If TUSSignalInfo(Item1^).Code < TUSSignalInfo(Item2^).Code then
      Result := -1
    else
      begin
      {$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
        If PtrUInt(TUSSignalInfo(Item1^).Value.PtrValue) > PtrUInt(TUSSignalInfo(Item2^).Value.PtrValue) then
          Result := +1
        else If PtrUInt(TUSSignalInfo(Item1^).Value.PtrValue) < PtrUInt(TUSSignalInfo(Item2^).Value.PtrValue) then
      {$IFDEF FPCDWM}{$POP}{$ENDIF}
          Result := -1
        else
          Result := 0;
      end;
  end;
end;

//------------------------------------------------------------------------------

Function TUSSignalQueue.ItemEquals(Item1,Item2: Pointer): Boolean;
begin
Result := (TUSSignalInfo(Item1^).Signal = TUSSignalInfo(Item2^).Signal) and
          (TUSSignalInfo(Item1^).Code = TUSSignalInfo(Item2^).Code) and
          (TUSSignalInfo(Item1^).Value.PtrValue = TUSSignalInfo(Item2^).Value.PtrValue);
end;

{-------------------------------------------------------------------------------
    TUSSignalQueue - public methods
-------------------------------------------------------------------------------}

constructor TUSSignalQueue.Create(MaxCount: Integer = -1);
begin
inherited Create(omFIFO,SizeOf(TUSSignalInfo),MaxCount);
end;

//------------------------------------------------------------------------------

Function TUSSignalQueue.IndexOf(Item: TUSSignalInfo): Integer;
begin
Result := inherited IndexOf(@Item);
end;

//------------------------------------------------------------------------------

Function TUSSignalQueue.Find(Item: TUSSignalInfo; out Index: Integer): Boolean;
begin
Result := inherited Find(@Item,Index);
end;

//------------------------------------------------------------------------------

procedure TUSSignalQueue.Push(Item: TUSSignalInfo);
begin
inherited Push(@Item);
end;

//------------------------------------------------------------------------------

Function TUSSignalQueue.Peek: TUSSignalInfo;
begin
inherited Peek(@Result);
end;

//------------------------------------------------------------------------------

Function TUSSignalQueue.Pop: TUSSignalInfo;
begin
inherited Pop(@Result);
end;

//------------------------------------------------------------------------------

Function TUSSignalQueue.Pick(Index: Integer): TUSSignalInfo;
begin
inherited Pick(Index,@Result);
end;


{===============================================================================
--------------------------------------------------------------------------------
                             TUSMulticastSignalEvent
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUSMulticastSignalEvent - class declaration
===============================================================================}
type
  TUSMulticastSignalEvent = class(TMulticastEvent)
  public
    Function IndexOf(const Handler: TUSSignalCallback): Integer; reintroduce; overload;
    Function IndexOf(const Handler: TUSSignalEvent): Integer; reintroduce; overload;
    Function Find(const Handler: TUSSignalCallback; out Index: Integer): Boolean; reintroduce; overload;
    Function Find(const Handler: TUSSignalEvent; out Index: Integer): Boolean; reintroduce; overload;
    Function Add(Handler: TUSSignalCallback): Integer; reintroduce; overload;
    Function Add(Handler: TUSSignalEvent): Integer; reintroduce; overload;
    Function Remove(const Handler: TUSSignalCallback): Integer; reintroduce; overload;
    Function Remove(const Handler: TUSSignalEvent): Integer; reintroduce; overload;
    procedure Call(Sender: TObject; const SignalInfo: TUSSignalInfo); reintroduce;
  end;

{===============================================================================
    TUSMulticastSignalEvent - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TUSMulticastSignalEvent - public methods
-------------------------------------------------------------------------------}

Function TUSMulticastSignalEvent.IndexOf(const Handler: TUSSignalCallback): Integer;
begin
Result := inherited IndexOf(MulticastEvent.TCallback(Handler));
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalEvent.IndexOf(const Handler: TUSSignalEvent): Integer;
begin
Result := inherited IndexOf(MulticastEvent.TEvent(Handler));
end;

//------------------------------------------------------------------------------

Function TUSMulticastSignalEvent.Find(const Handler: TUSSignalCallback; out Index: Integer): Boolean;
begin
Result := inherited Find(MulticastEvent.TCallback(Handler),Index);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalEvent.Find(const Handler: TUSSignalEvent; out Index: Integer): Boolean;
begin
Result := inherited Find(MulticastEvent.TEvent(Handler),Index);
end;

//------------------------------------------------------------------------------

Function TUSMulticastSignalEvent.Add(Handler: TUSSignalCallback): Integer;
begin
Result := inherited Add(MulticastEvent.TCallback(Handler),False);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalEvent.Add(Handler: TUSSignalEvent): Integer;
begin
Result := inherited Add(MulticastEvent.TEvent(Handler),False);
end;

//------------------------------------------------------------------------------

Function TUSMulticastSignalEvent.Remove(const Handler: TUSSignalCallback): Integer;
begin
Result := inherited Remove(MulticastEvent.TCallback(Handler),True);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalEvent.Remove(const Handler: TUSSignalEvent): Integer;
begin
Result := inherited Remove(MulticastEvent.TEvent(Handler),True);
end;

//------------------------------------------------------------------------------

procedure TUSMulticastSignalEvent.Call(Sender: TObject; const SignalInfo: TUSSignalInfo);
var
  i:          Integer;
  BreakProc:  Boolean;
begin
BreakProc := False;
For i := LowIndex to HighIndex do
  begin
    If fEntries[i].IsMethod then
      TUSSignalEvent(fEntries[i].HandlerMethod)(Sender,SignalInfo,BreakProc)
    else
      TUSSignalCallback(fEntries[i].HandlerProcedure)(Sender,SignalInfo,BreakProc);
    If BreakProc then
      Break{for i};
  end;
end;


{===============================================================================
--------------------------------------------------------------------------------
                               TUSSignalDispatcher
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUSSignalDispatcher - class declaration
===============================================================================}
type
  TUSSignalDispatcher = class(TCustomListObject)
  protected
    fThreadLock:      TCriticalSection;
    fUtilitySignals:  array of TUtilitySignal;
    fCount:           Integer;
    fOrphanSignals:   TUSSignalQueue;
    fOnOrphanSignal:  TUSMulticastSignalEvent;
    Function GetCapacity: Integer; override;
    procedure SetCapacity(Value: Integer); override;
    Function GetCount: Integer; override;
    procedure SetCount(Value: Integer); override;
    procedure Initialize; virtual;
    procedure Finalize; virtual;
    Function UtilitySignalFind(UtilitySignal: TUtilitySignal; out Index: Integer): Boolean; virtual;
  public
    constructor Create;
    destructor Destroy; override;
    Function LowIndex: Integer; override;
    Function HighIndex: Integer; override;
    Function UtilitySignalRegister(UtilitySignal: TUtilitySignal): Integer; virtual;
    Function UtilitySignalUnregister(UtilitySignal: TUtilitySignal): Integer; virtual;
    procedure DispatchFrom(var SignalBuffer: TUSSignalBuffer); virtual;
    procedure ProcessOrphans(var SignalBuffer: TUSSignalBuffer); virtual;
    Function OrphanSignalsRegister(Callback: TUSSignalCallback): Integer; virtual;
    Function OrphanSignalsRegister(Event: TUSSignalEvent): Integer; virtual;
    Function OrphanSignalsUnregister(Callback: TUSSignalCallback): Integer; virtual;
    Function OrphanSignalsUnregister(Event: TUSSignalEvent): Integer; virtual;
    procedure ProcessOrphanSignal; virtual;
    procedure ProcessOrphanSignals; virtual;
  end;

{===============================================================================
    TUSSignalDispatcher - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TUSSignalDispatcher - protected methods
-------------------------------------------------------------------------------}

Function TUSSignalDispatcher.GetCapacity: Integer;
begin
Result := Length(fUtilitySignals);
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.SetCapacity(Value: Integer);
begin
If Value < fCount then
  raise EUSInvalidValue.CreateFmt('TUSSignalDispatcher.SetCapacity: Invalid new capacity (%d).',[Value]);
If Value <> Length(fUtilitySignals) then
  SetLength(fUtilitySignals,Value);
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.GetCount: Integer;
begin
Result := fCount;
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.SetCount(Value: Integer);
begin
// just a no-op to consume the argument
If Value = fCount then
  fCount := Value;
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.Initialize;
begin
fThreadLock := TCriticalSection.Create;
fUtilitySignals := nil;
fCount := 0;
fOrphanSignals := TUSSignalQueue.Create(US_SZCOEF_QUEUE * 1024);
fOnOrphanSignal := TUSMulticastSignalEvent.Create(Self);
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.Finalize;
begin
FreeAndNil(fOnOrphanSignal);
FreeAndNil(fOrphanSignals);
fCount := 0;
SetLength(fUtilitySignals,0);
FreeAndNil(fThreadLock);
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.UtilitySignalFind(UtilitySignal: TUtilitySignal; out Index: Integer): Boolean;
var
  i:  Integer;
begin
// thread lock must be in effect before calling this method
Result := False;
Index := -1;
For i := LowIndex to HighIndex do
  If fUtilitySignals[i] = UtilitySignal then
    begin
      Index := i;
      Result := True;
      Break{For i};
    end;
end;

{-------------------------------------------------------------------------------
    TUSSignalDispatcher - public methods
-------------------------------------------------------------------------------}

constructor TUSSignalDispatcher.Create;
begin
inherited;
Initialize;
end;

//------------------------------------------------------------------------------

destructor TUSSignalDispatcher.Destroy;
begin
Finalize;
inherited;
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.LowIndex: Integer;
begin
fThreadLock.Enter;
try
  Result := Low(fUtilitySignals);
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.HighIndex: Integer;
begin
fThreadLock.Enter;
try
  Result := Pred(fCount);
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.UtilitySignalRegister(UtilitySignal: TUtilitySignal): Integer;
begin
fThreadLock.Enter;
try
  If not UtilitySignalFind(UtilitySignal,Result) then
    begin
      Grow;
      Result := fCount;
      fUtilitySignals[Result] := UtilitySignal;
      Inc(fCount);
    end;
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.UtilitySignalUnregister(UtilitySignal: TUtilitySignal): Integer;
var
  i:  Integer;
begin
fThreadLock.Enter;
try
  If UtilitySignalFind(UtilitySignal,Result) then
    begin
      For i := Result to Pred(HighIndex) do
        fUtilitySignals[i] := fUtilitySignals[i + 1];
      fUtilitySignals[HighIndex] := nil;
      Dec(fCount);
      Shrink;
    end;
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.DispatchFrom(var SignalBuffer: TUSSignalBuffer);

  Function StrIfThen(Condition: Boolean; const OnTrue,OnFalse: String): String;
  begin
    If Condition then
      Result := OnTrue
    else
      Result := OnFalse;
  end;

var
  i,j:    Integer;
  Index:  Integer;
begin
{$IFDEF FailOnSignalDrop}
If SignalBuffer.Head.DropCount > 0 then
  raise EUSSignalLost.CreateFmt('TUSSignalDispatcher.DispatchFrom: %d signal%s lost due to full buffer.',
    [SignalBuffer.Head.DropCount,StrIfThen(SignalBuffer.Head.DropCount <= 1,'','s')]);
{$ENDIF}
fThreadLock.Enter;
try
  For i := LowIndex to HighIndex do
    begin
      If SignalBuffer.Head.TakenCount >= SignalBuffer.Head.Count then
        Break{for i};
      fUtilitySignals[i].ThreadLock;
      try
        For j := 0 to Pred(SignalBuffer.Head.Count) do
          begin
            Index := (SignalBuffer.Head.First + j) mod Length(SignalBuffer.Signals);
            If not SignalBuffer.Signals[Index].Taken and
              (TObject(SignalBuffer.Signals[Index].Data) = fUtilitySignals[i]) then
              begin
                fUtilitySignals[i].AddSignal(SignalBuffer.Signals[Index].Code);
                SignalBuffer.Signals[Index].Taken := True;
                Inc(SignalBuffer.Head.TakenCount);
              end;
          end;
      finally
        fUtilitySignals[i].ThreadUnlock;
      end;
    end;
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.ProcessOrphans(var SignalBuffer: TUSSignalBuffer);
var
  i:            Integer;
  Index:        Integer;
  TempSigInfo:  TUSSignalInfo;
begin
{$IFDEF FailOnSignalDrop}
If SignalBuffer.Head.DropCount > 0 then
  raise EUSSignalLost.CreateFmt('TUSSignalDispatcher.ProcessOrphans: %d signal%s lost due to full buffer.',
    [SignalBuffer.Head.DropCount,StrIfThen(SignalBuffer.Head.DropCount <= 1,'','s')]);
{$ENDIF}
fThreadLock.Enter;
try
  For i := 0 to Pred(SignalBuffer.Head.Count) do
    begin
      Index := (SignalBuffer.Head.First + i) mod Length(SignalBuffer.Signals);
      If not SignalBuffer.Signals[Index].Taken then
        begin
          TempSigInfo.Signal := SignalBuffer.Signals[Index].Signal;
          TempSigInfo.Code := SignalBuffer.Signals[Index].Code;
          TempSigInfo.Value.PtrValue := SignalBuffer.Signals[Index].Data;
          fOrphanSignals.Push(TempSigInfo);
        end;
    end;
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.OrphanSignalsRegister(Callback: TUSSignalCallback): Integer;
begin
fThreadLock.Enter;
try
  Result := fOnOrphanSignal.Add(Callback);
finally
  fThreadLock.Leave;
end;
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSSignalDispatcher.OrphanSignalsRegister(Event: TUSSignalEvent): Integer;
begin
fThreadLock.Enter;
try
  Result := fOnOrphanSignal.Add(Event);
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

Function TUSSignalDispatcher.OrphanSignalsUnregister(Callback: TUSSignalCallback): Integer;
begin
fThreadLock.Enter;
try
  Result := fOnOrphanSignal.Remove(Callback);
finally
  fThreadLock.Leave;
end;
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSSignalDispatcher.OrphanSignalsUnregister(Event: TUSSignalEvent): Integer;
begin
fThreadLock.Enter;
try
  Result := fOnOrphanSignal.Remove(Event);
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.ProcessOrphanSignal;
begin
fThreadLock.Enter;
try
  If fOrphanSignals.Count > 0 then
    fOnOrphanSignal.Call(Self,fOrphanSignals.Pop);
finally
  fThreadLock.Leave;
end;
end;

//------------------------------------------------------------------------------

procedure TUSSignalDispatcher.ProcessOrphanSignals;
begin
fThreadLock.Enter;
try
  while fOrphanSignals.Count > 0 do
    fOnOrphanSignal.Call(Self,fOrphanSignals.Pop);
finally
  fThreadLock.Leave;
end;
end;


{===============================================================================
--------------------------------------------------------------------------------
                            Signal handling and setup
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Signal handling and setup - handler
===============================================================================}

{$IFDEF FPCDWM}{$PUSH}W5024{$ENDIF}
procedure SignalHandler(signo: cint; siginfo: psiginfo; context: Pointer); cdecl;
var
  Index:    Integer;
  ProcDone: Boolean;
begin
ProcDone := False;
repeat
  // lock the buffer (note this is a spin lock)
  If InterlockedExchange(GVAR_ModuleState.SignalBuffers.Lock,US_SIGRECVLOCK_LOCKED) = US_SIGRECVLOCK_UNLOCKED then
  try
    // we have the lock now, store the received signal
    with GVAR_ModuleState.SignalBuffers.Primary^ do
      begin
        Index := (Head.First + Head.Count) mod Length(Signals);
        Signals[Index].Taken := False;
        Signals[Index].Signal := signo;
        Signals[Index].Code := siginfo^.si_code;
        Signals[Index].Data := siginfo^._sifields._rt._sigval;
        // buffer is full, rewrite oldest entry
        If Head.Count >= Length(Signals) then
          begin
            Head.First := Succ(Head.First) mod Length(Signals);
            Head.Count := Length(Signals);
            Inc(Head.DropCount);
          end
        else Inc(Head.Count);
      end;
    ProcDone := True;
  finally
    // unlock the buffer
    InterlockedStore(GVAR_ModuleState.SignalBuffers.Lock,US_SIGRECVLOCK_UNLOCKED);
  end;
until ProcDone;
end;
{$IFDEF FPCDWM}{$POP}{$ENDIF}

{===============================================================================
    Signal handling and setup - signal setup
===============================================================================}

procedure SignalAllocate(PreallocatedSignal: cint = -1);
begin
If PreallocatedSignal < 0 then
  begin
    // get unused signal number
    GVAR_ModuleState.Signal := allocate_rtsig(1);
    If GVAR_ModuleState.Signal < 0 then
      raise EUSSignalSetupError.CreateFmt('SignalAllocate: Failed to allocate unused signal number (%d).',[errno_ptr^]);
  end
else GVAR_ModuleState.Signal := PreallocatedSignal;
// prepare signal set so we do not need to set it up everytime we need it
If sigemptyset(@GVAR_ModuleState.SignalSet) <> 0 then
  raise EUSSignalSetupError.CreateFmt('SignalAllocate: Emptying signal set failed (%d).',[errno_ptr^]);
If sigaddset(@GVAR_ModuleState.SignalSet,GVAR_ModuleState.Signal) <> 0 then
  raise EUSSignalSetupError.CreateFmt('SignalAllocate: Failed to add to signal set (%d).',[errno_ptr^]);
end;

//==============================================================================

procedure SignalBuffersAllocate;
begin
// prepare not only buffers but also their lock
GVAR_ModuleState.SignalBuffers.Lock := US_SIGRECVLOCK_UNLOCKED;
GVAR_ModuleState.SignalBuffers.Primary := AllocMem(SizeOf(TUSSignalBuffer)); // memory is zeroed
GVAR_ModuleState.SignalBuffers.Secondary := AllocMem(SizeOf(TUSSignalBuffer));
end;

//------------------------------------------------------------------------------

procedure SignalBuffersDeallocate;
begin
FreeMem(GVAR_ModuleState.SignalBuffers.Primary,SizeOf(TUSSignalBuffer));
FreeMem(GVAR_ModuleState.SignalBuffers.Secondary,SizeOf(TUSSignalBuffer));
end;

//==============================================================================

procedure SignalActionInstall(ExpectedHandler: Pointer = nil);
var
  SignalAction: sigaction_t;
begin
// check that the selected signal is really unused (does not have handler assigned)
FillChar(Addr(SignalAction)^,SizeOf(sigaction_t),0);
If sigaction(GVAR_ModuleState.Signal,nil,@SignalAction) <> 0 then
  raise EUSSignalSetupError.CreateFmt('SignalActionInstall: Failed to probe signal action (%d).',[errno_ptr^]);
If (@SignalAction.handler.sa_sigaction <> ExpectedHandler) and
  (@SignalAction.handler.sa_handler <> Pointer(SIG_DFL)) and
  (@SignalAction.handler.sa_handler <> Pointer(SIG_IGN)) then
  raise EUSSignalSetupError.CreateFmt('SignalActionInstall: Signal (#%d) handler has unexpected value.',[GVAR_ModuleState.Signal]);
// setup signal handler
FillChar(Addr(SignalAction)^,SizeOf(sigaction_t),0);
SignalAction.handler.sa_sigaction := SignalHandler;
SignalAction.sa_flags := SA_SIGINFO or SA_RESTART;
// do not block anything
If sigemptyset(Addr(SignalAction.sa_mask)) <> 0 then
  raise EUSSignalSetupError.CreateFmt('SignalActionInstall: Emptying signal set failed (%d).',[errno_ptr^]);
// install action
If sigaction(GVAR_ModuleState.Signal,@SignalAction,nil) <> 0 then
  raise EUSSignalSetupError.CreateFmt('SignalActionInstall: Failed to setup action for signal #%d (%d).',[GVAR_ModuleState.Signal,errno_ptr^]);
end;

//------------------------------------------------------------------------------

procedure SignalActionUninstall;
var
  SignalAction: sigaction_t;
begin
// clear signal handler
FillChar(Addr(SignalAction)^,SizeOf(sigaction_t),0);
{
  Field sa_sigaction is overlayed on sa_handler (which is explicitly assigned
  later), but to be sure we clear it anyway.
}
SignalAction.handler.sa_sigaction := nil;
@SignalAction.handler.sa_handler := Pointer(SIG_DFL); // default action (terminate)
If sigemptyset(Addr(SignalAction.sa_mask)) <> 0 then
  raise EUSSignalSetupError.CreateFmt('SignalActionUninstall: Emptying signal set failed (%d).',[errno_ptr^]);
If sigaction(GVAR_ModuleState.Signal,@SignalAction,nil) <> 0 then
  raise EUSSignalSetupError.CreateFmt('SignalActionUninstall: Failed to setup action for signal #%d (%d).',[GVAR_ModuleState.Signal,errno_ptr^]);
end;


{$IFDEF ModuleShared}
{===============================================================================
--------------------------------------------------------------------------------
                           Global (cross-module) state
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Global state - constants, types, variables
===============================================================================}
type
  TUSGlobalStateModule = record
    SignalFetchFrom:  procedure(SignalBuffer: PUSSignalBuffer); stdcall;
    MakePrimary:      procedure(ExpectedHandler: Pointer); stdcall;
  end;
  PUSGlobalStateModule  = ^TUSGlobalStateModule;

  TUSGlobalStateHead = record
    Version:    Integer;  // only assigned in initialization, no need for PGV lock
    Signal:     cint;
    Lock:       pthread_mutex_t;
  {
    All following fields (and the entire module list) must be protected by the
    preceding lock.
  }
    Capacity:   Integer;
    Count:      Integer;
    ModuleList: TPGVVariable;
  end;
  PUSGlobalStateHead = ^TUSGlobalStateHead;

const
  US_GLOBSTATE_HEAD_NAME = 'utilitysignal_shared_head';
  US_GLOBSTATE_LIST_NAME = 'utilitysignal_shared_list';

  US_GLOBSTATE_VERSION = 0;

  US_GLOBSTATE_LIST_CAPDELTA = 8;

{===============================================================================
    Global state - implementation
===============================================================================}
{-------------------------------------------------------------------------------
    Global state - auxiliary functions
-------------------------------------------------------------------------------}

Function GetModuleListSize(Capacity: Integer): TMemSize;
begin
If Capacity > 0 then
  Result := TMemSize(Capacity * SizeOf(TUSGlobalStateModule))
else
  raise EUSInvalidValue.CreateFmt('GS_GetModuleListSize: Invalid list capacity (%d).',[Capacity]);
end;

//------------------------------------------------------------------------------

Function GetModuleListItem(BaseAddress: PUSGlobalStateModule; Index: Integer): PUSGlobalStateModule;
begin
{$IFDEF FPCDWM}{$PUSH}W4055{$ENDIF}
If Index > 0 then
  Result := PUSGlobalStateModule(PtrUInt(BaseAddress) + PtrUInt(Index * SizeOf(TUSGlobalStateModule)))
else If Index = 0 then
  Result := BaseAddress
else
  raise EUSInvalidValue.CreateFmt('GetModuleListItem: Invalid list index (%d).',[Index]);
{$IFDEF FPCDWM}{$POP}{$ENDIF}
end;

//------------------------------------------------------------------------------

Function GetModuleListNext(ItemPtr: PUSGlobalStateModule): PUSGlobalStateModule;
begin
Result := ItemPtr;
Inc(Result);
end;

{-------------------------------------------------------------------------------
    Global state - exported functions
-------------------------------------------------------------------------------}

procedure SignalFetchFrom(SignalBuffer: PUSSignalBuffer); stdcall;
begin
GVAR_ModuleState.ProcessingLock.Enter;
try
  TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).DispatchFrom(SignalBuffer^);
finally
  GVAR_ModuleState.ProcessingLock.Leave;
end;
end;

//------------------------------------------------------------------------------

procedure MakePrimary(ExpectedHandler: Pointer); stdcall;
begin
// this needs to be locked to prevent races with SignalFetch
GVAR_ModuleState.ProcessingLock.Enter;
try
  // no need to allocate signal, it was already done by first primary module
  SignalBuffersAllocate;
  SignalActionInstall(ExpectedHandler);
  GVAR_ModuleState.GlobalInfo.IsPrimary := True;
finally
  GVAR_ModuleState.ProcessingLock.Leave;
end;
end;

{-------------------------------------------------------------------------------
    Global state - operation functions
-------------------------------------------------------------------------------}

procedure GlobalStateLock;
var
  GSHeadPtr:  PUSGlobalStateHead;
  RetVal:     cInt;
begin
// globals state head is never reallocated, so using its address directly is safe
GSHeadPtr := GVAR_ModuleState.GlobalInfo.HeadVariable^;
RetVal := pthread_mutex_lock(@GSHeadPtr^.Lock);
If RetVal = ESysEOWNERDEAD then
  begin
    If not PThrResChk(pthread_mutex_consistent(@GSHeadPtr^.Lock)) then
      raise EUSGlobalStateMutexError.CreateFmt('GlobalStateLock: Failed to make mutex consistent (%d).',[ThrErrorCode]);
  end
else If not PThrResChk(RetVal) then
  raise EUSGlobalStateMutexError.CreateFmt('GlobalStateLock: Failed to lock mutex (%d).',[ThrErrorCode]);
end;

//------------------------------------------------------------------------------

procedure GlobalStateUnlock;
var
  GSHeadPtr:  PUSGlobalStateHead;
begin
GSHeadPtr := GVAR_ModuleState.GlobalInfo.HeadVariable^;
If not PThrResChk(pthread_mutex_unlock(@GSHeadPtr^.Lock)) then
  raise EUSGlobalStateMutexError.CreateFmt('GlobalStateUnlock: Failed to unlock mutex (%d).',[ThrErrorCode]);
end;

//------------------------------------------------------------------------------

procedure GlobalStateAdd;
var
  GSHeadPtr:  PUSGlobalStateHead;
  GSListPtr:  PUSGlobalStateModule;
begin
GlobalStateLock;
try
  GSHeadPtr := GVAR_ModuleState.GlobalInfo.HeadVariable^;
  // reallocate if needed
  If GSHeadPtr^.Count >= GSHeadPtr^.Capacity then
    begin
      Inc(GSHeadPtr^.Capacity,US_GLOBSTATE_LIST_CAPDELTA);
      GSHeadPtr^.ModuleList := GlobVarRealloc(US_GLOBSTATE_LIST_NAME,GetModuleListSize(GSHeadPtr^.Capacity))^;
    end;
  Inc(GSHeadPtr^.Count);
  GSListPtr := GetModuleListItem(GSHeadPtr^.ModuleList^,Pred(GSHeadPtr^.Count));
  GSListPtr^.SignalFetchFrom := SignalFetchFrom;
  GSListPtr^.MakePrimary := MakePrimary;
finally
  GlobalStateUnlock;
end;
end;

//------------------------------------------------------------------------------

procedure GlobalStateRemove;
var
  GSHeadPtr:  PUSGlobalStateHead;
  GSListPtr:  PUSGlobalStateModule;
  GSItemPtr:  PUSGlobalStateModule;
  i,Index:    Integer;
begin
GlobalStateLock;
try
  GSHeadPtr := GVAR_ModuleState.GlobalInfo.HeadVariable^;
  GSListPtr := GSHeadPtr^.ModuleList^;
  Index := -1;
  GSItemPtr := GSListPtr;
  // find where we are
  For i := 0 to Pred(GSHeadPtr^.Count) do
    If (@GSItemPtr^.SignalFetchFrom = @SignalFetchFrom) and
       (@GSItemPtr^.MakePrimary = @MakePrimary) then
      begin
        Index := i;
        Break{For i};
      end
    else Inc(GSItemPtr);
  // if this module was found, remove it
  If Index >= 0 then
    begin
      GSItemPtr := GetModuleListItem(GSListPtr,Index);
      For i := Index to (GSHeadPtr^.Count - 2) do
        begin
          GSItemPtr^ := GetModuleListNext(GSItemPtr)^;
          Inc(GSItemPtr);
        end;
      GSItemPtr^.SignalFetchFrom := nil;
      GSItemPtr^.MakePrimary := nil;
      Dec(GSHeadPtr^.Count);
    end
  else raise EUSGlobalStateModListError.Create('GlobalStateRemove: Cannot find current module.');
finally
  GlobalStateUnlock;
end;
end;

{-------------------------------------------------------------------------------
    Global state - init/final functions
-------------------------------------------------------------------------------}

procedure GlobalStateInit;
var
  GSHeadPtr:  PUSGlobalStateHead;
  MutexAttr:  pthread_mutexattr_t;
begin
// PGV must be locked before calling this function
GSHeadPtr := GVAR_ModuleState.GlobalInfo.HeadVariable^;
FillChar(GSHeadPtr^,SizeOf(TUSGlobalStateHead),0);
GSHeadPtr^.Version := US_GLOBSTATE_VERSION;
// create state lock
If PThrResChk(pthread_mutexattr_init(@MutexAttr)) then
  try
    // make the mutex recursive and robust (it does not need to be process-shared)
    If not PThrResChk(pthread_mutexattr_settype(@MutexAttr,PTHREAD_MUTEX_RECURSIVE)) then
      raise EUSGlobalStateMutexError.CreateFmt('GlobalStateInit: Failed to set mutex attribute type (%d).',[ThrErrorCode]);
    If not PThrResChk(pthread_mutexattr_setrobust(@MutexAttr,PTHREAD_MUTEX_ROBUST)) then
      raise EUSGlobalStateMutexError.CreateFmt('GlobalStateInit: Failed to set mutex attribute robust (%d).',[ThrErrorCode]);
    If not PThrResChk(pthread_mutex_init(@GSHeadPtr^.Lock,@MutexAttr)) then
      raise EUSGlobalStateMutexError.CreateFmt('GlobalStateInit: Failed to init mutex (%d).',[ThrErrorCode]);
  finally
    pthread_mutexattr_destroy(@MutexAttr);
  end
else raise EUSGlobalStateMutexError.CreateFmt('GlobalStateInit: Failed to init mutex attributes (%d).',[ThrErrorCode]);
// prepare module list
GSHeadPtr^.Capacity := US_GLOBSTATE_LIST_CAPDELTA;
GSHeadPtr^.Count := 0;
// allocate module list
GSHeadPtr^.ModuleList := GlobVarAlloc(US_GLOBSTATE_LIST_NAME,GetModuleListSize(GSHeadPtr^.Capacity));
end;

//------------------------------------------------------------------------------

procedure GlobalStateOpen;
var
  VarSize:    TMemSize;
  GSHeadVar:  TPGVVariable;
  GSHeadPtr:  PUSGlobalStateHead;
begin
GlobVarLock;
try
  VarSize := SizeOf(TUSGlobalStateHead);
  case GlobVarGet(US_GLOBSTATE_HEAD_NAME,VarSize,GSHeadVar) of
    vgrCreated:
      begin
        // we have created the gobal (shared) state, initialize it
        GVAR_ModuleState.GlobalInfo.HeadVariable := GSHeadVar;
        GSHeadPtr := GSHeadVar^; // lock is acquired, so this is safe
        GlobalStateInit;
        // we are first so we are also primary
        GlobalStateAdd;
        GVAR_ModuleState.GlobalInfo.IsPrimary := True;
        // prepare signal
        SignalAllocate; // assigns GVAR_ModuleState.Signal
        SignalBuffersAllocate;
        SignalActionInstall;
        GSHeadPtr^.Signal := GVAR_ModuleState.Signal;
        GlobVarAcquire(GSHeadVar);
      end;
    vgrOpened:
      begin
      {
        We have opened the global state, so it already existed - this also
        means that the signal was already allocated elsewhere.
      }
        GVAR_ModuleState.GlobalInfo.HeadVariable := GSHeadVar;
        GSHeadPtr := GSHeadVar^;
        GSHeadPtr^.ModuleList := GlobVarGet(US_GLOBSTATE_LIST_NAME);
        // check that we got list variable with proper size
        If GlobVarSize(GSHeadPtr^.ModuleList) <> GetModuleListSize(GSHeadPtr^.Capacity) then
          raise EUSGlobalStateOpenError.Create('GlobalStateOpen: Module list has unexpected size.');
        GlobalStateAdd;
        GVAR_ModuleState.GlobalInfo.IsPrimary := False;
      {
        Do not allocate signal (only assign existing) and signal buffers and
        do not install signal action.
      }
        SignalAllocate(GSHeadPtr^.Signal);
        GlobVarAcquire(GSHeadVar);
      end;
    vgrSizeMismatch:
      raise EUSGlobalStateOpenError.Create('GlobalStateOpen: Size mismatch when opening module-shared state.');
  else
   {vgrError}
    raise EUSGlobalStateOpenError.Create('GlobalStateOpen: Failed to open module-shared state.');
  end;
finally
  GlobVarUnlock;
end;
end;

//------------------------------------------------------------------------------

procedure GlobalStateClose;
var
  GSHeadPtr:  PUSGlobalStateHead;
begin
GSHeadPtr := GVAR_ModuleState.GlobalInfo.HeadVariable^;
GlobVarLock;
try
  GlobalStateRemove;
  If GlobVarRelease(US_GLOBSTATE_HEAD_NAME) > 0 then
    begin
      // some other module is still using the global state...
      If GVAR_ModuleState.GlobalInfo.IsPrimary then
        begin
        {
          We are primary module, transfer primarity to other module - note that
          this module is no longer in the list.
        }
          If GSHeadPtr^.Count > 0 then
            begin
              If Assigned(@PUSGlobalStateModule(GSHeadPtr^.ModuleList^)^.MakePrimary) then
                PUSGlobalStateModule(GSHeadPtr^.ModuleList^)^.MakePrimary(@SignalHandler)
              else
                raise EUSGlobalStateCloseError.Create('GlobalStateClose: MakePrimary not assigned.');
            end
          else raise EUSGlobalStateCloseError.Create('GlobalStateClose: Empty module list.');
        {
          Do not call SignalActionUninstall - the action was replaced by the
          new primary module in MakePrimary.
        }
          SignalBuffersDeallocate;
        end
      // if we are not primary, there is nothing more to be done
    end
  else
    begin
      // we were the last module using the global state
      If GVAR_ModuleState.GlobalInfo.IsPrimary then
        begin
          // if last, we should be always primary, but meh...
          SignalActionUninstall;
          SignalBuffersDeallocate;
        end;
      // destroy the global state
      GlobVarFree(US_GLOBSTATE_LIST_NAME);
      If not PThrResChk(pthread_mutex_destroy(@GSHeadPtr^.Lock)) then
        raise EUSGlobalStateMutexError.CreateFmt('GlobalStateClose: Failed to destroy mutex (%d).',[ThrErrorCode]);
      GlobVarFree(US_GLOBSTATE_HEAD_NAME);
    end;
finally
  GlobVarUnlock;
end;
end;

{-------------------------------------------------------------------------------
    Global state - dispatch functions
-------------------------------------------------------------------------------}

procedure GlobalStateDispatch(SignalBuffer: PUSSignalBuffer);
var
  GSHeadPtr:  PUSGlobalStateHead;
  GSListPtr:  PUSGlobalStateModule;
  i:          Integer;
begin
GlobalStateLock;
try
  GSHeadPtr := GVAR_ModuleState.GlobalInfo.HeadVariable^;
  If GSHeadPtr^.Count > 1 then  // is there anyone but us?
    begin
      GSListPtr := GSHeadPtr^.ModuleList^;
      // traverse all modules and dispatch signal buffer to each one (except ourselves)
      For i := 0 to Pred(GSHeadPtr^.Count) do
        begin
          If Assigned(GSListPtr^.SignalFetchFrom) and
            (@GSListPtr^.SignalFetchFrom <> @SignalFetchFrom) then
            GSListPtr^.SignalFetchFrom(SignalBuffer);
          Inc(GSListPtr);
        end;
    end;
finally
  GlobalStateUnlock;
end;
end;

{$ENDIF}

{===============================================================================
--------------------------------------------------------------------------------
                                 Signal fetching
--------------------------------------------------------------------------------
===============================================================================}
// it is down here to remove a need for forward declarations

procedure SignalFetch;
var
  Temp:     PUSSignalBuffer;
  XchgDone: Boolean;
begin
GVAR_ModuleState.ProcessingLock.Enter;
try
{$IFDEF ModuleShared}
  // if we are not primary then there is nothing to fetch (buffers are not even allocated)
  If not GVAR_ModuleState.GlobalInfo.IsPrimary then
    Exit;
{$ENDIF}
  // block delivery of allocated signal so we can safely lock signal buffer
  If not PThrResChk(pthread_sigmask(SIG_BLOCK,@GVAR_ModuleState.SignalSet,nil)) then
    raise EUSSignalSetupError.CreateFmt('SignalProcess: Failed to block signal (%d).',[ThrErrorCode]);
  try
    XchgDone := False;
    repeat
      If InterlockedExchange(GVAR_ModuleState.SignalBuffers.Lock,US_SIGRECVLOCK_LOCKED) = US_SIGRECVLOCK_UNLOCKED then
      try
        // we have the lock, exchange buffers
        Temp := GVAR_ModuleState.SignalBuffers.Secondary;
        GVAR_ModuleState.SignalBuffers.Secondary := GVAR_ModuleState.SignalBuffers.Primary;
        GVAR_ModuleState.SignalBuffers.Primary := Temp;
        XchgDone := True;
      finally
        // unlock the buffer
        InterlockedStore(GVAR_ModuleState.SignalBuffers.Lock,US_SIGRECVLOCK_UNLOCKED);
      end;
    until XchgDone;
  finally
    If not PThrResChk(pthread_sigmask(SIG_UNBLOCK,@GVAR_ModuleState.SignalSet,nil)) then
      raise EUSSignalSetupError.CreateFmt('SignalProcess: Failed to unblock signal (%d).',[ThrErrorCode]);
  end;
  // now signal handler has clean (empty) buffer and secondary buffer contains received signals
  TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).DispatchFrom(GVAR_ModuleState.SignalBuffers.Secondary^);
{$IFDEF ModuleShared}
  GlobalStateDispatch(GVAR_ModuleState.SignalBuffers.Secondary);
{$ENDIF}
  TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).ProcessOrphans(GVAR_ModuleState.SignalBuffers.Secondary^);
  // clear the processed buffer
  FillChar(GVAR_ModuleState.SignalBuffers.Secondary^,SizeOf(TUSSignalBuffer),0);
finally
  GVAR_ModuleState.ProcessingLock.Leave;
end;
end;


{===============================================================================
--------------------------------------------------------------------------------
                                Utility functions
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    Utility functions - implementation
===============================================================================}

Function IsPrimaryModule: Boolean;
begin
{$IFDEF ModuleShared}
GVAR_ModuleState.ProcessingLock.Enter;
try
  Result := GVAR_ModuleState.GlobalInfo.IsPrimary;
finally
  GVAR_ModuleState.ProcessingLock.Leave;
end;
{$ELSE}
Result := True;
{$ENDIF}
end;

//------------------------------------------------------------------------------

Function AllocatedSignal: Integer;
begin
Result := GVAR_ModuleState.Signal;
end;

//------------------------------------------------------------------------------

Function GetCurrentProcessID: pid_t;
begin
Result := getpid;
end;

//==============================================================================

Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: TUSSignalValue; out Error: Integer): Boolean;
begin
Result := SendSignalTo(ProcessID,Signal,Value.PtrValue,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Integer; out Error: Integer): Boolean;
var
  Temp: TUSSignalValue;
begin
FillChar(Addr(Temp)^,SizeOf(Temp),0);
Temp.IntValue := Value;
Result := SendSignalTo(ProcessID,Signal,Temp.PtrValue,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Pointer; out Error: Integer): Boolean;
var
  SigValue: sigval_t;
begin
SigValue.sigval_ptr := Value;
If sigqueue(ProcessID,cint(Signal),SigValue) = 0 then
  begin
    Error := 0;
    Result := True;
  end
else
  begin
    Error := Integer(errno_ptr^);
    Result := False;
  end;
end;

//------------------------------------------------------------------------------

Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: TUSSignalValue): Boolean;
var
  Error: Integer;
begin
Result := SendSignalTo(ProcessID,Signal,Value,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Integer): Boolean;
var
  Error: Integer;
begin
Result := SendSignalTo(ProcessID,Signal,Value,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignalTo(ProcessID: pid_t; Signal: Integer; Value: Pointer): Boolean;
var
  Error: Integer;
begin
Result := SendSignalTo(ProcessID,Signal,Value,Error);
end;

//------------------------------------------------------------------------------

Function SendSignal(Value: TUSSignalValue; out Error: Integer): Boolean;
begin
Result := SendSignalTo(getpid,GVAR_ModuleState.Signal,Value,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignal(Value: Integer; out Error: Integer): Boolean;
begin
Result := SendSignalTo(getpid,GVAR_ModuleState.Signal,Value,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignal(Value: Pointer; out Error: Integer): Boolean;
begin
Result := SendSignalTo(getpid,GVAR_ModuleState.Signal,Value,Error);
end;

//------------------------------------------------------------------------------

Function SendSignal(Value: TUSSignalValue): Boolean;
var
  Error: Integer;
begin
Result := SendSignalTo(getpid,GVAR_ModuleState.Signal,Value,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignal(Value: Integer): Boolean;
var
  Error: Integer;
begin
Result := SendSignalTo(getpid,GVAR_ModuleState.Signal,Value,Error);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function SendSignal(Value: Pointer): Boolean;
var
  Error: Integer;
begin
Result := SendSignalTo(getpid,GVAR_ModuleState.Signal,Value,Error);
end;

{===============================================================================
--------------------------------------------------------------------------------
                               TUSSignalCodeQueue
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUSSignalCodeQueue - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TUSSignalCodeQueue - protected methods
-------------------------------------------------------------------------------}
{$IFDEF FailOnSignalDrop}
procedure TUSSignalCodeQueue.ItemDrop(Item: Pointer);
begin
raise EUSSignalLost.CreateFmt('TUSSignalCodeQueue.ItemDrop: Dropping queued signal code (%d).',[Integer(Item^)]);
end;
{$ENDIF}


{===============================================================================
--------------------------------------------------------------------------------
                           TUSMulticastSignalCodeEvent
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUSMulticastSignalCodeEvent - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TUSMulticastSignalCodeEvent - public methods
-------------------------------------------------------------------------------}

Function TUSMulticastSignalCodeEvent.IndexOf(const Handler: TUSSignalCodeCallback): Integer;
begin
Result := inherited IndexOf(MulticastEvent.TCallback(Handler));
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalCodeEvent.IndexOf(const Handler: TUSSignalCodeEvent): Integer;
begin
Result := inherited IndexOf(MulticastEvent.TEvent(Handler));
end;

//------------------------------------------------------------------------------

Function TUSMulticastSignalCodeEvent.Find(const Handler: TUSSignalCodeCallback; out Index: Integer): Boolean;
begin
Result := inherited Find(MulticastEvent.TCallback(Handler),Index);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalCodeEvent.Find(const Handler: TUSSignalCodeEvent; out Index: Integer): Boolean;
begin
Result := inherited Find(MulticastEvent.TEvent(Handler),Index);
end;

//------------------------------------------------------------------------------

Function TUSMulticastSignalCodeEvent.Add(Handler: TUSSignalCodeCallback): Integer;
begin
Result := inherited Add(MulticastEvent.TCallback(Handler),False);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalCodeEvent.Add(Handler: TUSSignalCodeEvent): Integer;
begin
Result := inherited Add(MulticastEvent.TEvent(Handler),False);
end;

//------------------------------------------------------------------------------

Function TUSMulticastSignalCodeEvent.Remove(const Handler: TUSSignalCodeCallback): Integer;
begin
Result := inherited Remove(MulticastEvent.TCallback(Handler));
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

Function TUSMulticastSignalCodeEvent.Remove(const Handler: TUSSignalCodeEvent): Integer;
begin
Result := inherited Remove(MulticastEvent.TEvent(Handler));
end;

//------------------------------------------------------------------------------

procedure TUSMulticastSignalCodeEvent.Call(Sender: TObject; Code: Integer);
var
  i:          Integer;
  BreakProc:  Boolean;
begin
BreakProc := False;
For i := LowIndex to HighIndex do
  begin
    If fEntries[i].IsMethod then
      TUSSignalCodeEvent(fEntries[i].HandlerMethod)(Sender,Code,BreakProc)
    else
      TUSSignalCodeCallback(fEntries[i].HandlerProcedure)(Sender,Code,BreakProc);
    If BreakProc then
      Break{for i};
  end;
end;


{===============================================================================
--------------------------------------------------------------------------------
                                 TUtilitySignal
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TUtilitySignal - class implementation
===============================================================================}
{-------------------------------------------------------------------------------
    TUtilitySignal - protected methods
-------------------------------------------------------------------------------}

Function TUtilitySignal.GetCoalesceSignals: Boolean;
begin
// since this property can be accessed from multiple threads, we have to protect it
ThreadLock;
try
  Result := fCoalesceSignals;
finally
  ThreadUnlock;
end;
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.SetCoalesceSignals(Value: Boolean);
begin
ThreadLock;
try
  fCoalesceSignals := Value;
finally
  ThreadUnlock;
end;
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.Initialize;
begin
fRegisteredOnIdle := False;
fThreadLock := TCriticalSection.Create;
fReceivedSignals := TUSSignalCodeQueue.Create(US_SZCOEF_QUEUE * 256);
fCreatorThread := gettid;
fObserveThread := True;
fCoalesceSignals := False;
fOnSignal := TUSMulticastSignalCodeEvent.Create(Self);
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).UtilitySignalRegister(Self);
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.Finalize;
begin
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).UtilitySignalUnregister(Self);
FreeAndNil(fOnSignal);
FreeAndNil(fReceivedSignals);
FreeAndNil(fThreadLock);
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.ThreadLock;
begin
fThreadLock.Enter;
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.ThreadUnlock;
begin
fThreadLock.Leave;
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.AddSignal(Code: Integer);
var
  Index:  Integer;
begin
// thread lock must be activated externally
If fCoalesceSignals then
  begin
    If not fReceivedSignals.Find(Code,Index) then
      fReceivedSignals.Push(Code);
  end
else fReceivedSignals.Push(Code);
end;

//------------------------------------------------------------------------------

Function TUtilitySignal.CheckThread: Boolean;
begin
If fObserveThread then
  Result := fCreatorThread = gettid
else
  Result := True;
end;

//------------------------------------------------------------------------------

{$IFDEF FPCDWM}{$PUSH}W5024{$ENDIF}
procedure TUtilitySignal.OnAppIdleHandler(Sender: TObject; var Done: Boolean);
begin
ProcessSignals;
end;
{$IFDEF FPCDWM}{$POP}{$ENDIF}

{-------------------------------------------------------------------------------
    TUtilitySignal - public methods
-------------------------------------------------------------------------------}

class Function TUtilitySignal.Signal: Integer;
begin
Result := AllocatedSignal;
end;

//------------------------------------------------------------------------------

constructor TUtilitySignal.Create(CanRegisterForOnIdle: Boolean = True);
begin
inherited Create;
Initialize;
If CanRegisterForOnIdle then
  RegisterForOnIdle;
end;

//------------------------------------------------------------------------------

destructor TUtilitySignal.Destroy;
begin
UnregisterFromOnIdle;
Finalize;
inherited;
end;

//------------------------------------------------------------------------------

Function TUtilitySignal.RegisterForOnIdle: Boolean;
begin
Result := False;
{$IFDEF LCL}
If CheckThread and (pthread_equal(GetCurrentThreadID,MainThreadID) <> 0) then
  begin
    Application.AddOnIdleHandler(OnAppIdleHandler,False);
    fRegisteredOnIdle := True;
    Result := True;
  end;
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.UnregisterFromOnIdle;
begin
{$IFDEF LCL}
If fRegisteredOnIdle then
  Application.RemoveOnIdleHandler(OnAppIdleHandler);
{$ENDIF}
fRegisteredOnIdle := False;
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.ProcessSignal;
begin
SignalFetch;
If CheckThread then
  begin
    ThreadLock;
    try
      If fReceivedSignals.Count > 0 then
        fOnSignal.Call(Self,fReceivedSignals.Pop);
    finally
      ThreadUnlock;
    end;
  end;
end;

//------------------------------------------------------------------------------

procedure TUtilitySignal.ProcessSignals;
begin
SignalFetch;
If CheckThread then
  begin
    ThreadLock;
    try
      while fReceivedSignals.Count > 0 do
        fOnSignal.Call(Self,fReceivedSignals.Pop);
    finally
      ThreadUnlock;
    end;
  end;
end;


{===============================================================================
--------------------------------------------------------------------------------
                                 Orphan signals
--------------------------------------------------------------------------------
===============================================================================}

procedure RegisterForOrphanSignals(Callback: TUSSignalCallback);
begin
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).OrphanSignalsRegister(Callback);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

procedure RegisterForOrphanSignals(Event: TUSSignalEvent);
begin
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).OrphanSignalsRegister(Event);
end;

//------------------------------------------------------------------------------

procedure UnregisterFromOrphanSignals(Callback: TUSSignalCallback);
begin
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).OrphanSignalsUnregister(Callback);
end;

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

procedure UnregisterFromOrphanSignals(Event: TUSSignalEvent);
begin
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).OrphanSignalsUnregister(Event);
end;

//==============================================================================

procedure ProcessOrphanSignal;
begin
SignalFetch;
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).ProcessOrphanSignal;
end;

//------------------------------------------------------------------------------

procedure ProcessOrphanSignals;
begin
SignalFetch;
TUSSignalDispatcher(GVAR_ModuleState.Dispatcher).ProcessOrphanSignals;
end;


{===============================================================================
--------------------------------------------------------------------------------
                      Unit initialization and finalization
--------------------------------------------------------------------------------
===============================================================================}

procedure LibraryInitialize;
begin
GVAR_ModuleState.ProcessingLock := TCriticalSection.Create;
GVAR_ModuleState.Dispatcher := TUSSignalDispatcher.Create;
{$IFDEF ModuleShared}
GlobalStateOpen;
{$ELSE}
SignalAllocate;
SignalBuffersAllocate;
SignalActionInstall;
{$ENDIF}
end;

//------------------------------------------------------------------------------

procedure LibraryFinalize;
begin
{$IFDEF ModuleShared}
GlobalStateClose;
{$ELSE}
SignalActionUninstall;
SignalBuffersDeallocate;
{$ENDIF}
// there is no need to deallocate the signal (it is not possible anyway)
FreeAndNil(GVAR_ModuleState.Dispatcher);
FreeandNil(GVAR_ModuleState.ProcessingLock);
end;

//==============================================================================

initialization
  LibraryInitialize;

finalization
  LibraryFinalize;

end.

