with Ada.Real_Time; use Ada.Real_Time;
with Ada.Real_Time.Timing_Events; use Ada.Real_Time.Timing_Events;
with Gcode.Planner; use Gcode.Planner;
with System;

package body Stepper is

   type Do_Step_Array is array (Axis_Name) of Boolean;

   type Stepper_Data_Type is record
      Has_Segment : Boolean := False;
      --  Does the stepper still has a segment to execute

      Seg : Segment;

      Step_Count : Steps;
      Counter : Step_Position;

      Do_Step : Do_Step_Array := (others => False);
      --  Tells which axis has to do a step at the next iteration

      Directions       : Axis_Directions := (others => Forward);
      --  Direction of steps for eaxh axis

      Block_Steps : Step_Position;
      --  Steps for the current Motion block each axis
      Block_Event_Count : Steps;
      --  Step count for the current block

      Set_Step_Callback : Set_Step_Pin_Proc := null;
      Clear_Step_Callback : Clear_Step_Pin_Proc := null;
      Set_Direction_Callback : Set_Direction_Pin_Proc := null;

      Current_Position : Step_Position := (others => 0);
      --  Keep track of the actuall position of the machine
   end record;

   St_Data : Stepper_Data_Type;

   type Step_Timing_Event is new Timing_Event with record
      Do_Step : Do_Step_Array;
   end record;

   ----------------
   -- Step_Pulse --
   ----------------

   protected Step_Pulse is
      pragma Priority (System.Interrupt_Priority'Last);

      procedure Start_Step_Cycle (Do_Step : Do_Step_Array;
                                  Directions  : Axis_Directions);
      procedure Set_Step_Pins (Event : in out Timing_Event);
      procedure Clear_Step_Pins (Event : in out Timing_Event);
   private
      Set_Event   : Step_Timing_Event;
      Clear_Event : Step_Timing_Event;

      --  Step pins timming
      --    Direction delay   Step delay
      --  |-----------------|------------|
      --  ^                 ^            ^
      --  Set  direction    Set step     Clear step

      Direction_Delay : Time_Span := Microseconds (5);
      Step_Delay      : Time_Span := Microseconds (5);
   end Step_Pulse;

   protected body Step_Pulse is
      ----------------------
      -- Start_Step_Cycle --
      ----------------------

      procedure Start_Step_Cycle (Do_Step     : Do_Step_Array;
                                  Directions  : Axis_Directions)
      is
         Now : Time;
      begin
         Step_Pulse.Set_Event.Do_Step := Do_Step;
         Step_Pulse.Clear_Event.Do_Step := Do_Step;

         if St_Data.Set_Direction_Callback /= null then
            --  Set direction pins now
            for Axis in Axis_Name loop
               --  Set_Direction pin
               St_Data.Set_Direction_Callback (Axis, Directions (Axis));
            end loop;
         end if;

         Now := Clock;

         if Direction_Delay = Microseconds (0) then
            --  Set step pins imediatly
            Set_Step_Pins (Timing_Event (Set_Event));
         else
            --  Schedule the timming evnet that will set the step pins
            Set_Handler (Set_Event, Now + Direction_Delay,
                         Set_Step_Pins'Access);
         end if;

         if Direction_Delay = Microseconds (0)
           and then
             Step_Delay = Microseconds (0)
         then
            --  Clear step pins imediatly
            Clear_Step_Pins (Timing_Event (Clear_Event));
         else
            --  Schedule the timming evnet that will clear the step pins
            Set_Handler (Clear_Event,  Now + Direction_Delay + Step_Delay,
                         Clear_Step_Pins'Access);
         end if;
      end Start_Step_Cycle;

      -------------------
      -- Set_Step_Pins --
      -------------------

      procedure Set_Step_Pins (Event : in out Timing_Event) is
         Do_Step : constant Do_Step_Array :=
           Step_Timing_Event (Timing_Event'Class (Event)).Do_Step;
      begin
         if St_Data.Set_Step_Callback /= null then
            for Axis in Axis_Name loop
               if Do_Step (Axis) then
                  St_Data.Set_Step_Callback (Axis);
               end if;
            end loop;
         end if;
      end Set_Step_Pins;

      ---------------------
      -- Clear_Step_Pins --
      ---------------------

      procedure Clear_Step_Pins (Event : in out Timing_Event) is
         Do_Step : constant Do_Step_Array :=
           Step_Timing_Event (Timing_Event'Class (Event)).Do_Step;
      begin
         if St_Data.Set_Step_Callback /= null then
            for Axis in Axis_Name loop
               if Do_Step (Axis) then
                  St_Data.Clear_Step_Callback (Axis);
               end if;
            end loop;
         end if;
      end Clear_Step_Pins;
   end Step_Pulse;

   function Execute_Step_Event return Boolean is
   begin

      Step_Pulse.Start_Step_Cycle (St_Data.Do_Step,
                                   St_Data.Directions);

      --  Reset step instruction
      St_Data.Do_Step := (others => False);

      if not St_Data.Has_Segment then
         if Get_Next_Segment (St_Data.Seg) then
            St_Data.Has_Segment := True;
            --  Process new segment

            St_Data.Step_Count := St_Data.Seg.Step_Count;
            St_Data.Directions := St_Data.Seg.Directions;

            if St_Data.Seg.New_Block then
               --  This is the first segment of a new block

               --  Prep data for bresenham algorithm
               St_Data.Counter := (others => 0);
               St_Data.Block_Steps := St_Data.Seg.Block_Steps;
               St_Data.Block_Event_Count :=
                 St_Data.Seg.Block_Event_Count;

            end if;
         else
            --  No segment to exectute
            return False;
         end if;
      end if;

      --  Bresenham for each axis
      for Axis in Axis_Name loop
         St_Data.Counter (Axis) :=
           St_Data.Counter (Axis) + St_Data.Block_Steps (Axis);

         if St_Data.Counter (Axis) > St_Data.Block_Event_Count then
            St_Data.Do_Step (Axis) := True;
            St_Data.Counter (Axis) :=
              St_Data.Counter (Axis) - St_Data.Block_Event_Count;
            if St_Data.Directions (Axis) = Forward then
               St_Data.Current_Position (Axis) :=
                 St_Data.Current_Position (Axis) + 1;
            else
               St_Data.Current_Position (Axis) :=
                 St_Data.Current_Position (Axis) + 1;
            end if;
         else
            St_Data.Do_Step (Axis) := False;
         end if;
      end loop;

      St_Data.Step_Count := St_Data.Step_Count - 1;
      --  Check end of segement
      if St_Data.Step_Count = 0 then
         St_Data.Has_Segment := False;
      end if;

      return True;
   end Execute_Step_Event;

   ---------------------------
   -- Set_Stepper_Callbacks --
   ---------------------------

   procedure Set_Stepper_Callbacks (Set_Step       : Set_Step_Pin_Proc;
                                    Clear_Step     : Clear_Step_Pin_Proc;
                                    Set_Direcetion : Set_Direction_Pin_Proc)
   is
   begin
      St_Data.Set_Step_Callback := Set_Step;
      St_Data.Clear_Step_Callback := Clear_Step;
      St_Data.Set_Direction_Callback := Set_Direcetion;
   end Set_Stepper_Callbacks;

end Stepper;
