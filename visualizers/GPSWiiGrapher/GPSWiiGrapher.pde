//
// GPSWiiGrapher.pde --Graph output files from the GPSWiiLogger Arduino project
//
// 2008, Tod E. Kurt, http://todbot.com/blog/
//
//

import javax.swing.*;

ArrayList datapoints;

boolean debug = true;  // set to true to get some debug output

PFont font;

float scale;
int dX,dY;
int w,h;
boolean drawscale = true;  // 's' key to toggle

int range = 4;

void setup() {
    size(640,480);
    frameRate(10);
    font = loadFont("Verdana-12.vlw"); 
    textFont(font);
    
    File file = loadFile();
    datapoints = parseFile( file );

    if( file == null ) {
        println("no file selected. goodbye.");
        exit();
    }
    
    if(debug) {
        println("\ndatapoints:"+datapoints.size());
        for( int i=0; i< datapoints.size(); i++ )
            println(i+":"+datapoints.get(i));
    }
    println("setup done");
    w = width;
    h = height;
    scale = 1;
}


void draw() { 
    background(100);
    fill(30);
    text("use arrow keys to scan through data and move graph around", 10,10);
    text("use +/- keys to zoom in/out on data, and enter to reset, s toggles scale", 10,20);
    plotPoints( 20,20, w-20,h-20 );
}

// convert -range/2 to +range/2 value to pixel value from 0 to h
float toPixelY(float y) {
    return map(y, -(range/2),(range/2), 20, h-20);
    //return y;
}

void plotPoints(int xo, int yo, int w, int h ) {
    pushMatrix();
    translate(xo,yo+dY);
    scale( scale );

    if( drawscale ) {
        int ysteps = 4;
        stroke(50);  fill(50);
        line( 0, toPixelY(-range/2), 0, toPixelY(range/2));
        line( 0, toPixelY(0),        w, toPixelY(0));
        for( int i=1; i<ysteps; i++ ) {
            float r = (range/2) * i * (1.0/ysteps);
            float yp = toPixelY(r); 
            float ym = toPixelY(-r); 
            line( 0, yp, 10, yp );
            line( 0, ym, 10, ym );
            text("+"+nf(r,1,1), 10, yp+5 );
            text("-"+nf(r,1,1), 10, ym+1 );
        }
    }

    translate(dX, 0);  // move graph (and x-axis of scale) if needed

    if( drawscale ) {
        int num = datapoints.size();
        int xsteps = (num<100) ? 10 : datapoints.size()/20;
        // each datapoint is 1/10th second, so 10 is one second, 50 is 5 secs
        for( int i=1; i<xsteps; i++ ) {
            line( i*50, toPixelY(-0.05), i*50, toPixelY(+0.05) );
            text( int(i*50/10), i*50, toPixelY(-0.10) );
        }
    }

    DataPoint dpl = (DataPoint)datapoints.get(0);
    fill(255,0,0);
    text("X",0,toPixelY(dpl.x));
    fill(0,255,0);
    text("Y",0,toPixelY(dpl.y));
    fill(0,0,255);
    text("Z",0,toPixelY(dpl.z));
    int s = 5;
    int xb= 5;
    for( int i=0; i<datapoints.size(); i++ ) {
        DataPoint dp = (DataPoint)datapoints.get(i);
        stroke(255,0,0);
        line( xb+ i-1, toPixelY(dpl.x), xb+ i, toPixelY(dp.x) );
        stroke(0,255,0);
        line( xb+ i-1, toPixelY(dpl.y), xb+ i, toPixelY(dp.y) );
        stroke(0,0,255);
        line( xb+ i-1, toPixelY(dpl.z), xb+ i, toPixelY(dp.z) );
        dpl = (DataPoint) datapoints.get(i);
    }
    popMatrix();
}


void keyPressed() {
    if( key == CODED ) {
        if( keyCode == UP ) 
            dY -=10;
        else if( keyCode == DOWN )
            dY += 10;
        else if( keyCode == LEFT )
            dX -= 10;
        else if( keyCode == RIGHT ) 
            dX += 10;
    }
    else if( key == '-' || key == '_' ) 
        scale -= 0.1;
    else if( key == '+' || key == '=' ) 
        scale += 0.1;
    else if( key == ENTER || key == RETURN ) {
        dX = 0; dY = 0; scale = 1;
    }
    else if( key == 's' ) {
        drawscale = !drawscale;
    }

}


//
// Bring up a javax filechooser dialog box and open a file
//
File loadFile() {
    // set system look and feel
    try {
        UIManager.setLookAndFeel(UIManager.getSystemLookAndFeelClassName());
    }
    catch (Exception e) {
        e.printStackTrace(); 
    }
    
    final JFileChooser fc = new JFileChooser();  //Create a file chooser
    
    //In response to a button click:
    int returnVal = fc.showOpenDialog(this);
    
    if (returnVal != JFileChooser.APPROVE_OPTION) {
        println("Open command cancelled by user.");
        return null;
    }
    File file = fc.getSelectedFile();
    // see if it's a txt file
    // (better to write a function and check for all supported extensions)
    if (file.getName().endsWith("txt") ||
        file.getName().endsWith("TXT")) {
        return file;
    }
    return null;
}

//
float convertToGs( int v ) {
    //return ((float)(v-127)*range)/127/2;  // centered around 127
    return map( v-127, -128, 127, -range/2, range/2);
}

//
// Parse an open file for GPSWiiLogger data
// format is: 
// GPRMC line, '|'-separated XYZ hex-coded accelerometer data line, ...
//
ArrayList parseFile( File file ) {
    println("parseFile: "+file);
    if( file==null ) 
        return null;
    
    String lines[] = loadStrings(file); // loadStrings can take File Object too
    //int numpoints = (lines.length/2) * 10; // every  2lines has 10 datapoints

    ArrayList dps = new ArrayList();  // array of data points
    //DataPoint[] dp = new DataPoint[ numpoints ]; 
    int p = 0;

    long millistamp = 0;
    long millistart = 0;
    DataPoint ldp =null;  // last valid datapoint
    for (int i = 0; i < lines.length; i++) {
        String l = lines[i];
        if(debug) println(l); 
        // parse GPS time
        if( l.substring(0,6).equals("$GPRMC") ) { // we're on a GPS line
            if(debug) print("GPRMC line: ");
            long tmillis;
            tmillis =  60*60*1000 * Integer.parseInt( l.substring(7,9) );
            tmillis +=    60*1000 * Integer.parseInt( l.substring(9,11) ); 
            tmillis +=       1000 * Integer.parseInt( l.substring(11,13) );
            if( millistart==0 ) millistart = tmillis;  // set zero point
            if(debug) println("tmillis:"+tmillis);
            millistamp = tmillis;
        }
        else {          // otherwise line contains |-separated datapoints
            String[] strs = split(l, '|');
            if(debug) println("data strs len:"+strs.length);
            if( strs.length <= 1 ) continue; // bad line
            int millistep = 1000/(strs.length-1);
            for( int j=0; j< strs.length; j++  ) {
                String xyzstr = strs[j];
                if( xyzstr != null && xyzstr.length() == 6 ) {
                    if(debug) print(" xyz:"+ xyzstr);
                    int x = Integer.parseInt( xyzstr.substring(0,2),16 );
                    int y = Integer.parseInt( xyzstr.substring(2,4),16 );
                    int z = Integer.parseInt( xyzstr.substring(4,6),16 );
                    float xx = convertToGs(x);
                    float yy = convertToGs(y);
                    float zz = convertToGs(z);
                    DataPoint dp = new DataPoint( xx,yy,zz, millistamp);
                    if( x == 0 && y == 0 && z == 0 ) // use last point if zero
                        dp = ldp;
                    ldp = dp;  // save this as last point
                    millistamp += millistep;
                    dps.add( dp );
                }
            }
        }
    }
    
    return dps;
}


// simple class to hold timestamped data points
class DataPoint {
    //int x,y,z; // x,y,z value of point
    float x,y,z;
    long msec;  // time point occured in milliseconds
    DataPoint(float xx, float yy, float zz, long ms) {
        x = xx;  // why are bytes signed?  so stupid 
        y = yy;
        z = zz;
        msec = ms;
    }
    String toString() {
        return "{"+msec+":"+x+","+y+","+z+"}";
    }
        
}

