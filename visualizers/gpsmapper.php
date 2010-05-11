<?php
  //
  //  gpsmapper.php -- Map GPS data in NMEA format as a line on Google Maps
  //
  //  Yes, similar to gpsvisualizer.com, but simpler
  //  and makes self-contained pages that can be saved since the
  //  gps data is placed in a javascript data structure
  //
  //  2008, Tod E. Kurt, http://todbot.com/blog/ 
  //

// define constant which contains the maximum file size in bytes
define('MAX_FILE_SIZE', 4000000);

// get your own http://code.google.com/apis/maps/signup.html .
// this one is mine
$GMAPS_API_KEY="ABQIAAAACQjOJc5gYSwEjxBS6KpT3BQ2Q2jvRtN_rLoWUsbjaUjz6dBvBRTDU71629dhBHjqL4sYF-VNzADmTw";

//
function parseGPSData() {
    $fileData = file_get_contents($_FILES['frmfile']['tmp_name']);
    $lines = split("[\r\n]", $fileData); // FIXME: works on linux?
    foreach( $lines as $line_num => $line) {
        if( preg_match("/^$GPRMC/", $line) ) { 
            $fields = explode(",", $line);
            preg_match("/(\d+)(\d\d)\.(\d+)/",$fields[3],$matches);
            $lat = $matches[1] + (($matches[2] .".". $matches[3]) / 60);
            preg_match("/(\d+)(\d\d)\.(\d+)/",$fields[5],$matches);
            $lon = $matches[1] + (($matches[2] .".". $matches[3]) / 60);
            if( $fields[4] == 'S' ) $lat = -$lat;
            if( $fields[6] == 'W' ) $lon = -$lon;
            if( $lat !=0 && $lon !=0 ) { // add new point
                $points[] = array('time'=>$fields[1],'lat'=>$lat,'lon'=>$lon);
            }
        }
    }
    $retval = array('points' => $points, 'max' => $max, 'min' => $min);
    return $retval;
}

//---

if (array_key_exists('btn', $_POST)) { // signifies upload button pressed

    $frmfile = $_FILES['frmfile']['name'];

    //Find the extension
    $flext = pathinfo($_FILES['frmfile']['name']);
    $ext = strtolower($flext['extension']);
    
    // create new file name
    $file = str_replace(' ', '_', $_FILES['frmfile']['name']);
    //$file = str_replace(' ', '_', $_POST['frmname'].'.'.$ext);
    $file = strtolower($file);

    // create variable and assign the formatted value of MAX_FILE_SIZE to it
    $maxfs = number_format(MAX_FILE_SIZE/1024, 1).'KB';
    $fsize = false;
    
    // check the file size
    if ($_FILES['frmfile']['size'] > 0 && 
        $_FILES['frmfile']['size'] <= MAX_FILE_SIZE) {
        $fsize = true;
    }
    
    // allow MIME file types
    $filetype = array('image/gif','image/jpeg','image/pjpeg','image/png');
    $ftype = true;
    
    //if ($ftype && $fsize && $_POST['frmname'] != '') {
    if ($ftype && $fsize && $file != '') {
        
        switch($_FILES['frmfile']['error']) {
        case 0:  // success
            $parsed = parseGPSData();
            break;
        case 3:
            $msg = 'Error.<br />Please try again.';
            break;
        case 4:
            $msg = 'Please select file';
            break;
        default:
            $msg = 'Error - please contact administrator';
        }
    }
    else {
        $msg = $_FILES['frmfile']['name'].' cannot be uploaded.<br />';
        if(!$ftype) {
            $msg .= 'Acceptable file formats are: .gif, .jpg, .png<br />';
        }
        if(!$fsize) {
            $msg .= 'Maximum file size is '.$maxfs;
        }
    }
    
} // if button
?>

<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:v="urn:schemas-microsoft-com:vml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<title> GPS NMEA Google Mapper </title>
<style type="text/css">
<!--
body {
	font-family:Arial, Helvetica, sans-serif;
	font-size:10pt;
	color:#444;
}
#frm_upload, #tbl_upload, #btn, #sbm {
	margin:0px;
	padding:0px;
}
#tbl_upload {
	border-top:solid 1px #aaa;
	border-left:solid 1px #aaa;
}
#tbl_upload th, #tbl_upload td {
	border-right:solid 1px #aaa;
	border-bottom:solid 1px #aaa;
	text-align:left;
	vertical-align:top;
}
#tbl_upload th {
	padding:3px 10px 0px 10px;
	background-color:#f1f1f1;
	font-weight:bold;
}
#tbl_upload td {
	padding:3px;
}
.frmfld {
	border:1px solid #aaa;
	width:300px;
}
#btn, #sbm {
	height:20px;
	width:120px;
	display:block;
}
#btn {
	background-color:transparent;
	border:none;
	cursor:pointer;
}
#sbm {
	border:solid 1px #aaa;
	background:url(button.gif) repeat-x 0px 50%;
}
.warning {
	color:#990000;
	font-weight:bold;
}
-->
</style>
    <script src="http://maps.google.com/maps?file=api&amp;v=2&amp;key=<?php echo $GMAPS_API_KEY ?>"
      type="text/javascript"></script>
    <script type="text/javascript">

    // get parsed gps data into javascript format
    var mypoints = eval(<?php echo json_encode($parsed) ?>);

    function initialize() {
      if (GBrowserIsCompatible()) {
        var map = new GMap2(document.getElementById("map_canvas"));
        map.setMapType(G_HYBRID_MAP);
        map.addControl(new GSmallMapControl());
        map.addControl(new GMapTypeControl());
        
        if( mypoints == null  ) {
            map.setCenter(new GLatLng(34.14,-118.15), 12); // default
        } else { 
            var ps = mypoints.points;
            var bounds = new GLatLngBounds();
            var glls = new Array();
            for( var i=0; i< ps.length; i++ ) {
                var gll = new GLatLng(ps[i]['lat'],ps[i]['lon']);
                glls[glls.length] = gll;
                bounds.extend( gll );
            }
            var polyline = new GPolyline( glls, "#ff00ff", 3, 0.8);
            map.addOverlay(polyline);
            map.setCenter( bounds.getCenter(), map.getBoundsZoomLevel(bounds));
        }
      }
    }
    </script>
</head>

<body onload="initialize()" onunload="GUnload()">

<h2>Upload a GPS NMEA file to be mapped </h2> <br/>

<?php if(isset($msg)) { echo '<p class="warning">'.$msg.'</p>'; } ?>

<form action="" method="post" enctype="multipart/form-data" name="frm_upload" id="frm_upload">
  <table border="0" cellspacing="0" cellpadding="0" id="tbl_upload">
    <tr>
      <th scope="row"><label for="frmfile">File:</label></th>
      <td>
      <input type="hidden" name="MAX_FILE_SIZE" value="<?php echo MAX_FILE_SIZE; ?>" />
      <input name="frmfile" type="file" id="frmfile" size="30" /></td>
      <td>
      <label for="btn" id="sbm">
      <input type="submit" name="btn" id="btn" value="Upload" />
      </label>
      </td>
    </tr>
  </table>
</form>

<br/>

  <?php if(isset($frmfile)) { echo "<b>$frmfile </b><br/>"; } ?>

<br/>

  <div id="map_canvas" style="width: 500px; height: 300px"></div>
  <div id="message"></div>


  </body>
</html>

</body>
</html>
