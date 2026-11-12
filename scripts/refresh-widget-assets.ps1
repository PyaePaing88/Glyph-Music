$ErrorActionPreference = 'Stop'
$res = Join-Path $PSScriptRoot '../android/app/src/main/res'
function Write-Resource($Name, $Content) {
    $file = Join-Path $res $Name
    New-Item -ItemType Directory -Force (Split-Path $file) | Out-Null
    [IO.File]::WriteAllText($file, $Content, [Text.UTF8Encoding]::new($false))
}
Write-Resource 'drawable/widget_background.xml' @'
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#58131313" />
    <corners android:radius="24dp" />
</shape>
'@
Write-Resource 'drawable/widget_play_background.xml' @'
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="oval">
    <solid android:color="#D71920" />
</shape>
'@
Write-Resource 'drawable/widget_album_placeholder.xml' @'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="128dp" android:height="128dp" android:viewportWidth="128" android:viewportHeight="128">
    <path android:fillColor="#34363C" android:pathData="M64,0a64,64 0,1 0,0 128a64,64 0,1 0,0 -128" />
    <path android:fillColor="#17181C" android:pathData="M64,8a56,56 0,1 0,0 112a56,56 0,1 0,0 -112" />
    <path android:strokeColor="#55575D" android:strokeWidth="1" android:fillColor="#00000000" android:pathData="M64,18a46,46 0,1 0,0 92a46,46 0,1 0,0 -92M64,26a38,38 0,1 0,0 76a38,38 0,1 0,0 -76M64,34a30,30 0,1 0,0 60a30,30 0,1 0,0 -60" />
    <path android:fillColor="#EFEFEC" android:pathData="M64,47a17,17 0,1 0,0 34a17,17 0,1 0,0 -34" />
    <path android:fillColor="#D93840" android:pathData="M64,60a4,4 0,1 0,0 8a4,4 0,1 0,0 -8" />
</vector>
'@
foreach ($entry in @{
    play='M9,5L20,12L9,19Z'
    pause='M7,5H11V19H7ZM14,5H18V19H14Z'
    next='M6,5L16,12L6,19ZM17,5H20V19H17Z'
    previous='M18,5L8,12L18,19ZM4,5H7V19H4Z'
}.GetEnumerator()) {
    $color = '#F5F5F2'
    Write-Resource "drawable/widget_$($entry.Key).xml" "<vector xmlns:android=`"http://schemas.android.com/apk/res/android`" android:width=`"24dp`" android:height=`"24dp`" android:viewportWidth=`"24`" android:viewportHeight=`"24`"><path android:fillColor=`"$color`" android:pathData=`"$($entry.Value)`" /></vector>"
}
$art = '<ImageView android:id="@+id/widget_record" android:layout_width="{0}" android:layout_height="{1}" {2} android:src="@drawable/widget_album_placeholder" android:scaleType="fitCenter" android:contentDescription="Album artwork" />'
$title = '<TextView android:id="@+id/track_title" android:layout_width="match_parent" android:layout_height="22dp" android:text="Your music. Your space." android:textColor="#FFFFFF" android:textSize="16sp" android:fontFamily="sans-serif-medium" android:maxLines="1" android:ellipsize="end" />'
$artist = '<TextView android:id="@+id/track_artist" android:layout_width="match_parent" android:layout_height="20dp" android:text="Open Glyph Music" android:textColor="#CECECC" android:textSize="12sp" android:maxLines="1" android:ellipsize="end" />'
# A small dot-matrix signature, with ordinary readable type for track details.
$glyphs = @{
    G=@('01111','10000','10000','10111','10001','10001','01110')
    L=@('10000','10000','10000','10000','10000','10000','11111')
    Y=@('10001','10001','01010','00100','00100','00100','00100')
    P=@('11110','10001','10001','11110','10000','10000','10000')
    H=@('10001','10001','10001','11111','10001','10001','10001')
}
$brandDots = ''
$brandLetters = 'GLYPH'
for ($letter = 0; $letter -lt $brandLetters.Length; $letter++) {
    $pattern = $glyphs[[string]$brandLetters[$letter]]
    for ($row = 0; $row -lt 7; $row++) {
        for ($col = 0; $col -lt 5; $col++) {
            if ($pattern[$row][$col] -eq '1') {
                $dotX = ($letter * 6 + $col) * 2 + 1
                $dotY = $row * 2 + 1
                $brandDots += "M$dotX,$dotY m-0.6,0 a0.6,0.6 0,1 0,1.2 0 a0.6,0.6 0,1 0,-1.2 0 "
            }
        }
    }
}
Write-Resource 'drawable/widget_brand.xml' "<vector xmlns:android=`"http://schemas.android.com/apk/res/android`" android:width=`"60dp`" android:height=`"14dp`" android:viewportWidth=`"60`" android:viewportHeight=`"14`"><path android:fillColor=`"#CCCCCA`" android:pathData=`"$brandDots`" /></vector>"
$brand = '<ImageView android:layout_width="60dp" android:layout_height="14dp" android:layout_marginBottom="4dp" android:src="@drawable/widget_brand" android:contentDescription="Glyph Music" />'
$controls = @'
<LinearLayout android:layout_width="match_parent" android:layout_height="48dp" android:gravity="center_vertical" android:orientation="horizontal">
    <ImageButton android:id="@+id/previous_track" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp" android:padding="4dp" android:background="@android:color/transparent" android:src="@drawable/widget_previous" android:contentDescription="Previous track" />
    <ImageButton android:id="@+id/play_pause" android:layout_width="48dp" android:layout_height="48dp" android:padding="12dp" android:background="@drawable/widget_play_background" android:src="@drawable/widget_play" android:contentDescription="Play" />
    <ImageButton android:id="@+id/next_track" android:layout_width="0dp" android:layout_weight="1" android:layout_height="48dp" android:padding="4dp" android:background="@android:color/transparent" android:src="@drawable/widget_next" android:contentDescription="Next track" />
</LinearLayout>
'@
$shortcuts = @'
<LinearLayout android:id="@+id/widget_shortcuts" android:layout_width="match_parent" android:layout_height="36dp" android:orientation="horizontal">
    <TextView android:id="@+id/queue_shortcut" android:layout_width="0dp" android:layout_weight="1" android:layout_height="match_parent" android:gravity="center" android:text="Queue" android:textSize="11sp" android:textColor="#E1E1E4" />
    <TextView android:id="@+id/playlists_shortcut" android:layout_width="0dp" android:layout_weight="1" android:layout_height="match_parent" android:gravity="center" android:text="Playlists" android:textSize="11sp" android:textColor="#E1E1E4" />
</LinearLayout>
'@
$layouts = @{
    glyph_compact = '<LinearLayout android:layout_width="match_parent" android:layout_height="match_parent" android:gravity="center_vertical" android:orientation="horizontal">' + ($art -f '80dp','80dp','android:layout_marginEnd="12dp"') + '<LinearLayout android:layout_width="0dp" android:layout_weight="1" android:layout_height="wrap_content" android:orientation="vertical">' + $brand + $title + $artist + $controls + '</LinearLayout></LinearLayout>'
    glyph_widget = ($art -f 'match_parent','0dp','android:layout_weight="1"') + $title + $artist + $controls
    glyph_tall = $brand + ($art -f 'match_parent','0dp','android:layout_weight="1" android:layout_marginVertical="8dp"') + $title + $artist + $controls + $shortcuts
}
foreach ($entry in $layouts.GetEnumerator()) {
    $xml = '<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android" android:id="@+id/widget_root" android:layout_width="match_parent" android:layout_height="match_parent" android:background="@drawable/widget_background" android:clipToOutline="true"><ImageView android:id="@+id/widget_surface" android:layout_width="match_parent" android:layout_height="match_parent" android:scaleType="fitXY" android:importantForAccessibility="no" /><LinearLayout android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="vertical" android:padding="12dp">' + $entry.Value + '</LinearLayout></FrameLayout>'
    Write-Resource "layout/$($entry.Key).xml" $xml
    Write-Resource "layout/$($entry.Key)_preview.xml" ($xml.Replace('Your music. Your space.', 'First Light').Replace('Open Glyph Music','The quiet hours'))
}
foreach ($entry in @(
    @{Name='compact';Layout='glyph_compact';W=4;H=2;Width=270;Height=140;Shape='wide'},
    @{Name='medium';Layout='glyph_widget';W=2;H=2;Width=140;Height=140;Shape='square'},
    @{Name='large';Layout='glyph_tall';W=2;H=4;Width=140;Height=300;Shape='tall'}
)) {
    $xml = @"
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="$($entry.Width)dp" android:minHeight="$($entry.Height)dp"
    android:minResizeWidth="110dp" android:minResizeHeight="130dp"
    android:targetCellWidth="$($entry.W)" android:targetCellHeight="$($entry.H)"
    android:updatePeriodMillis="0" android:initialLayout="@layout/$($entry.Layout)"
    android:previewLayout="@layout/$($entry.Layout)_preview"
    android:previewImage="@drawable/widget_preview_$($entry.Shape)"
    android:description="@string/widget_description"
    android:resizeMode="horizontal|vertical" android:widgetCategory="home_screen" />
"@
    Write-Resource "xml/glyph_$($entry.Name)_widget.xml" $xml
}
# Use the supplied transparent record image; inset it into Android's adaptive safe area.
$foreground = '<inset xmlns:android="http://schemas.android.com/apk/res/android" android:inset="16.67%"><bitmap android:src="@drawable/glyph_app_icon" android:gravity="fill" android:filter="true" /></inset>'
Write-Resource 'drawable/ic_glyph_foreground.xml' $foreground
Write-Resource 'drawable/ic_glyph_monochrome.xml' $foreground
$legacy = '<bitmap xmlns:android="http://schemas.android.com/apk/res/android" android:src="@mipmap/ic_launcher" android:gravity="fill" android:filter="true" />'
Write-Resource 'drawable/ic_launcher_glyph.xml' $legacy
Write-Resource 'mipmap-anydpi/ic_launcher_glyph.xml' $legacy
Write-Resource 'mipmap-anydpi-v26/ic_launcher_glyph.xml' '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/glyph_icon_background" /><foreground android:drawable="@drawable/ic_glyph_foreground" /></adaptive-icon>'
Write-Resource 'mipmap-anydpi-v33/ic_launcher_glyph.xml' '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@color/glyph_icon_background" /><foreground android:drawable="@drawable/ic_glyph_foreground" /><monochrome android:drawable="@drawable/ic_glyph_monochrome" /></adaptive-icon>'
Write-Resource 'values/glyph_resources.xml' @'
<resources>
    <string name="app_name">Glyph Music</string>
    <string name="widget_wide">Glyph Music &#183; Wide (4&#215;2)</string>
    <string name="widget_square">Glyph Music &#183; Square (2&#215;2)</string>
    <string name="widget_tall">Glyph Music &#183; Tall (2&#215;4)</string>
    <string name="widget_description">Translucent music controls with album artwork, song title, and artist. Resize for square, wide, or tall layouts.</string>
    <color name="glyph_icon_background">#141518</color>
</resources>
'@
# Legacy launcher previews are actual PNGs, with transparent outer margins.
Add-Type -AssemblyName System.Drawing
$iconSource = [Drawing.Bitmap]::new((Join-Path $res 'drawable-nodpi/glyph_app_icon.png'))
foreach ($density in @{mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192}.GetEnumerator()) {
    $icon = [Drawing.Bitmap]::new($density.Value, $density.Value)
    $graphics = [Drawing.Graphics]::FromImage($icon)
    $graphics.InterpolationMode = 'HighQualityBicubic'
    $graphics.DrawImage($iconSource, 0, 0, $density.Value, $density.Value)
    $icon.Save((Join-Path $res "mipmap-$($density.Key)/ic_launcher.png"), [Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $icon.Dispose()
}
$iconSource.Dispose()
foreach ($shape in @('wide','square','tall')) {
    $w = if ($shape -eq 'wide') { 600 } else { 300 }
    $h = if ($shape -eq 'tall') { 600 } else { 300 }
    $bitmap = [Drawing.Bitmap]::new($w, $h)
    $g = [Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $path = [Drawing.Drawing2D.GraphicsPath]::new()
    $radius = 48
    $path.AddArc(8,8,$radius,$radius,180,90)
    $path.AddArc(($w-8-$radius),8,$radius,$radius,270,90)
    $path.AddArc(($w-8-$radius),($h-8-$radius),$radius,$radius,0,90)
    $path.AddArc(8,($h-8-$radius),$radius,$radius,90,90)
    $path.CloseFigure()
    $brush = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(155,24,24,24))
    $g.FillPath($brush,$path)
    $pen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(90,255,255,255),2)
    $ax=28; $ay=28; $size=60; $tx=28; $ty=100
    if ($shape -eq 'wide') { $size=180; $ay=60; $tx=232; $ty=66 }
    if ($shape -eq 'tall') { $size=220; $ax=40; $ay=60; $ty=324 }
    $g.FillEllipse([Drawing.Brushes]::Black,$ax,$ay,$size,$size)
    for ($ring=1; $ring -le 3; $ring++) {
        $gap=$size*0.065*$ring
        $g.DrawEllipse([Drawing.Pens]::DimGray,($ax+$gap),($ay+$gap),($size-2*$gap),($size-2*$gap))
    }
    $g.FillEllipse([Drawing.Brushes]::WhiteSmoke,($ax+$size*.38),($ay+$size*.38),($size*.24),($size*.24))
    $g.FillEllipse([Drawing.Brushes]::IndianRed,($ax+$size*.47),($ay+$size*.47),($size*.06),($size*.06))
    $font = [Drawing.Font]::new('Segoe UI',20,[Drawing.FontStyle]::Bold)
    $small = [Drawing.Font]::new('Segoe UI',13)
    $g.DrawString('First Light',$font,[Drawing.Brushes]::WhiteSmoke,$tx,$ty)
    $g.DrawString('The quiet hours',$small,[Drawing.Brushes]::LightGray,$tx,($ty+40))
    $cy = if ($shape -eq 'wide') { 194 } elseif ($shape -eq 'tall') { 490 } else { 232 }
    $cx = if ($shape -eq 'wide') { 394 } else { 150 }
    $g.FillEllipse([Drawing.Brushes]::Firebrick,($cx-26),($cy-26),52,52)
    $points = [Drawing.PointF[]]@([Drawing.PointF]::new(($cx-7),($cy-12)),[Drawing.PointF]::new(($cx+12),$cy),[Drawing.PointF]::new(($cx-7),($cy+12)))
    $g.FillPolygon([Drawing.Brushes]::WhiteSmoke,$points)
    $g.DrawString([string][char]0x2039,$font,[Drawing.Brushes]::WhiteSmoke,($cx-88),($cy-22))
    $g.DrawString([string][char]0x203A,$font,[Drawing.Brushes]::WhiteSmoke,($cx+66),($cy-22))
    $bitmap.Save((Join-Path $res "drawable/widget_preview_$shape.png"),[Drawing.Imaging.ImageFormat]::Png)
    $font.Dispose(); $small.Dispose(); $pen.Dispose(); $brush.Dispose(); $path.Dispose(); $g.Dispose(); $bitmap.Dispose()
}
