with STM32.Device; use STM32.Device;
with STM32.GPIO; use STM32.GPIO;
with Gcode; use Gcode;

package Step_Control is
   procedure Initalize;
private

   type GPIO_Point_Per_Axis is array (Axis_Name) of GPIO_Point;

   M1_Step_GPIO : GPIO_Point renames PD8;
   M2_Step_GPIO : GPIO_Point renames PD10;
   M3_Step_GPIO : GPIO_Point renames PB10;

   M1_Dir_GPIO : GPIO_Point renames PD15;
   M2_Dir_GPIO : GPIO_Point renames PD12;
   M3_Dir_GPIO : GPIO_Point renames PB12;

   M1_Not_Enable_GPIO : GPIO_Point renames PD14;
   M2_Not_Enable_GPIO : GPIO_Point renames PB14;
   M3_Not_Enable_GPIO : GPIO_Point renames PE15;

   Step_GPIO : constant GPIO_Point_Per_Axis :=
     (X_Axis => M2_Step_GPIO,
      Y_Axis => M1_Step_GPIO,
      Z_Axis => M3_Step_GPIO);

   Dir_GPIO : constant GPIO_Point_Per_Axis :=
     (X_Axis => M2_Dir_GPIO,
      Y_Axis => M1_Dir_GPIO,
      Z_Axis => M3_Dir_GPIO);

   Not_Enable_GPIO : constant GPIO_Point_Per_Axis :=
     (X_Axis => M2_Not_Enable_GPIO,
      Y_Axis => M1_Not_Enable_GPIO,
      Z_Axis => M3_Not_Enable_GPIO);

   Analysis_Point : constant GPIO_Point := PD13;
   --  This GPIO can be used to mesure the time spent en step event
end Step_Control;
