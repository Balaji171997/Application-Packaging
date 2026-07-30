##############################################################
# Theme.ps1
# One shared, modern dark theme for EVERY window/dialog/popup.
# Apply-PbTheme merges an implicit-style ResourceDictionary into a
# Window's resources, so all Buttons / TextBoxes / ComboBoxes /
# CheckBoxes / ListBoxes pick it up automatically (no per-control
# restyling). Keyed styles (PbAccentButton) are opt-in for CTAs.
#
# Palette - professional, restrained, "smooth": layered graphite
# surfaces, soft low-contrast borders, ONE refined teal-cyan accent
# used sparingly (CTA / focus / selection). Easy on the eyes.
#   bg #181A1F  surface #21242B  raised #2A2E36  input #14161A
#   border #2F343D (soft)  text #E7E9ED  muted #939BA7
#   accent #2BA6B8 (teal-cyan)  ok #57BE8C  warn #E0BE7C  danger #DE7079
##############################################################

$script:PbThemeXaml = @'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

  <!-- palette -->
  <SolidColorBrush x:Key="PbBg"        Color="#FF181A1F"/>
  <SolidColorBrush x:Key="PbSurface"   Color="#FF21242B"/>
  <SolidColorBrush x:Key="PbRaised"    Color="#FF2A2E36"/>
  <SolidColorBrush x:Key="PbRaisedHov" Color="#FF333845"/>
  <SolidColorBrush x:Key="PbInputBg"   Color="#FF14161A"/>
  <SolidColorBrush x:Key="PbBorder"    Color="#FF2F343D"/>
  <SolidColorBrush x:Key="PbBorderSub" Color="#FF24282F"/>
  <SolidColorBrush x:Key="PbText"      Color="#FFE7E9ED"/>
  <SolidColorBrush x:Key="PbMuted"     Color="#FF939BA7"/>
  <SolidColorBrush x:Key="PbAccent"    Color="#FF2BA6B8"/>
  <SolidColorBrush x:Key="PbAccentHov" Color="#FF37B8CA"/>
  <SolidColorBrush x:Key="PbAccentPrs" Color="#FF23899A"/>
  <SolidColorBrush x:Key="PbAccentDim" Color="#FF18353D"/>
  <SolidColorBrush x:Key="PbOk"        Color="#FF57BE8C"/>
  <SolidColorBrush x:Key="PbWarn"      Color="#FFE0BE7C"/>
  <SolidColorBrush x:Key="PbDanger"    Color="#FFDE7079"/>

  <!-- ===== Button (implicit): rounded, subtle, clear hover ===== -->
  <Style TargetType="Button">
    <Setter Property="Background" Value="{StaticResource PbRaised}"/>
    <Setter Property="Foreground" Value="{StaticResource PbText}"/>
    <Setter Property="BorderBrush" Value="{StaticResource PbBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="13,5"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="MinHeight" Value="28"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="SnapsToDevicePixels" Value="True"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="6" Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{StaticResource PbRaisedHov}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource PbAccent}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="#FF1F232A"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="b" Property="Background" Value="#FF20242B"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource PbBorderSub}"/>
              <Setter Property="Foreground" Value="#FF5B626D"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- accent / primary CTA button (Next, Create) -->
  <Style x:Key="PbAccentButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background" Value="{StaticResource PbAccent}"/>
    <Setter Property="BorderBrush" Value="{StaticResource PbAccent}"/>
    <Setter Property="Foreground" Value="White"/>
    <Setter Property="FontWeight" Value="SemiBold"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="6" Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="{StaticResource PbAccentHov}"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource PbAccentHov}"/>
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="b" Property="Background" Value="{StaticResource PbAccentPrs}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="b" Property="Background" Value="#FF2E3641"/>
              <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource PbBorderSub}"/>
              <Setter Property="Foreground" Value="#FF6B7280"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- ===== TextBox (implicit): rounded, accent focus. Small vertical padding +
       centered content so the common Height=24/26 boxes never clip. ===== -->
  <Style TargetType="TextBox">
    <Setter Property="Background" Value="{StaticResource PbInputBg}"/>
    <Setter Property="Foreground" Value="{StaticResource PbText}"/>
    <Setter Property="BorderBrush" Value="{StaticResource PbBorder}"/>
    <Setter Property="BorderThickness" Value="1"/>
    <Setter Property="Padding" Value="8,2"/>
    <Setter Property="CaretBrush" Value="{StaticResource PbAccent}"/>
    <Setter Property="SelectionBrush" Value="{StaticResource PbAccent}"/>
    <Setter Property="VerticalContentAlignment" Value="Center"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TextBox">
          <Border x:Name="b" CornerRadius="5" Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                  Padding="{TemplateBinding Padding}">
            <ScrollViewer x:Name="PART_ContentHost" VerticalAlignment="{TemplateBinding VerticalContentAlignment}"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsKeyboardFocusWithin" Value="True">
              <Setter TargetName="b" Property="BorderBrush" Value="{StaticResource PbAccent}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Foreground" Value="#FF6A717C"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- ===== CheckBox (implicit): rounded accent box ===== -->
  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{StaticResource PbText}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Cursor" Value="Hand"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Border x:Name="box" Width="16" Height="16" CornerRadius="4" VerticalAlignment="Center"
                    Background="{StaticResource PbInputBg}" BorderBrush="{StaticResource PbBorder}" BorderThickness="1">
              <Path x:Name="tick" Width="9" Height="9" Stretch="Uniform" Visibility="Collapsed"
                    Data="M 0 4 L 3 7 L 8 1" Stroke="White" StrokeThickness="1.6"
                    StrokeEndLineCap="Round" StrokeStartLineCap="Round"/>
            </Border>
            <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="box" Property="Background" Value="{StaticResource PbAccent}"/>
              <Setter TargetName="box" Property="BorderBrush" Value="{StaticResource PbAccent}"/>
              <Setter TargetName="tick" Property="Visibility" Value="Visible"/>
            </Trigger>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="box" Property="BorderBrush" Value="{StaticResource PbAccentHov}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Foreground" Value="#FF6A717C"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- ===== ListBoxItem (implicit): calm hover/selection ===== -->
  <Style TargetType="ListBoxItem">
    <Setter Property="Foreground" Value="{StaticResource PbText}"/>
    <Setter Property="Padding" Value="6,4"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ListBoxItem">
          <Border x:Name="b" Background="Transparent" CornerRadius="4" Padding="{TemplateBinding Padding}">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="b" Property="Background" Value="#FF282D36"/>
            </Trigger>
            <Trigger Property="IsSelected" Value="True">
              <Setter TargetName="b" Property="Background" Value="{StaticResource PbAccentDim}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- ===== ComboBox (implicit): full dark template so the selected text + the
       drop-down list are always readable (the partial style hid the text). ===== -->
  <Style TargetType="ComboBoxItem">
    <Setter Property="Foreground" Value="{StaticResource PbText}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="Padding" Value="9,6"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBoxItem">
          <Border x:Name="b" Background="Transparent" Padding="{TemplateBinding Padding}">
            <ContentPresenter/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsHighlighted" Value="True">
              <Setter TargetName="b" Property="Background" Value="{StaticResource PbAccentDim}"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ComboBox">
    <Setter Property="Foreground" Value="{StaticResource PbText}"/>
    <Setter Property="Background" Value="{StaticResource PbInputBg}"/>
    <Setter Property="BorderBrush" Value="{StaticResource PbBorder}"/>
    <Setter Property="FontFamily" Value="Segoe UI"/>
    <Setter Property="FontSize" Value="12"/>
    <Setter Property="MinHeight" Value="26"/>
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBox">
          <Grid>
            <ToggleButton x:Name="tb" Focusable="False" ClickMode="Press"
                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
              <ToggleButton.Template>
                <ControlTemplate TargetType="ToggleButton">
                  <Border x:Name="bd" CornerRadius="5" Background="{StaticResource PbInputBg}"
                          BorderBrush="{StaticResource PbBorder}" BorderThickness="1">
                    <Grid>
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="22"/></Grid.ColumnDefinitions>
                      <Path Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center"
                            Data="M 0 0 L 7 0 L 3.5 4 Z" Fill="{StaticResource PbMuted}"/>
                    </Grid>
                  </Border>
                  <ControlTemplate.Triggers>
                    <Trigger Property="IsMouseOver" Value="True">
                      <Setter TargetName="bd" Property="BorderBrush" Value="{StaticResource PbAccent}"/>
                    </Trigger>
                  </ControlTemplate.Triggers>
                </ControlTemplate>
              </ToggleButton.Template>
            </ToggleButton>
            <ContentPresenter x:Name="cp" Margin="9,0,26,0" VerticalAlignment="Center" HorizontalAlignment="Left"
                              Content="{TemplateBinding SelectionBoxItem}"
                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                              TextElement.Foreground="{StaticResource PbText}" IsHitTestVisible="False"/>
            <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False"
                   IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Fade">
              <Border Background="{StaticResource PbSurface}" BorderBrush="{StaticResource PbBorder}" BorderThickness="1"
                      CornerRadius="5" Margin="0,3,0,0" MaxHeight="260"
                      MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                <ScrollViewer><ItemsPresenter/></ScrollViewer>
              </Border>
            </Popup>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Foreground" Value="#FF6A717C"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

</ResourceDictionary>
'@

$script:PbTheme = $null
function Apply-PbTheme {
    param($Window)
    if (-not $Window) { return }
    try {
        if (-not $script:PbTheme) {
            $script:PbTheme = [Windows.Markup.XamlReader]::Parse($script:PbThemeXaml)
        }
        $Window.Resources.MergedDictionaries.Add($script:PbTheme)
    } catch { if (Get-Command Write-Log -EA SilentlyContinue) { Write-Log "Apply-PbTheme failed: $($_.Exception.Message)" Warning } }
}
