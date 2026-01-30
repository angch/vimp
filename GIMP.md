# GIMP Features

This document provides a comprehensive list of features found in the GIMP source code (`ref/gimp`).

## Tools (`app/tools`)

### Selection Tools
- **Rectangle Select**: Select a rectangular region
- **Ellipse Select**: Select an elliptical region
- **Free Select**: Select a hand-drawn region with free segments
- **Fuzzy Select**: Select a contiguous region on the basis of color
- **By Color Select**: Select regions with similar colors
- **Intelligent Scissors**: Select shapes using intelligent edge-fitting
- **Foreground Select**: Select a region containing foreground objects
- **Bucket Fill**: Fill selected area with a color or pattern

### Paint Tools
- **Brush**: Paint smooth strokes using a brush
- **Pencil**: Hard edge painting using a brush
- **Airbrush**: Paint using a brush with variable pressure
- **Ink**: Calligraphy-style painting
- **MyPaint Brush**: Paint with MyPaint brushes
- **Eraser**: Erase to background or transparency
- **Clone**: Selectively copy from an image or pattern, using a brush
- **Heal**: Heal image irregularities
- **Perspective Clone**: Clone from an image source after applying a perspective transformation
- **Convolve**: Blur or sharpen using a brush
- **Smudge**: Smudge selectively using a brush
- **Dodge/Burn**: Lighten or darken strokes causing dodge or burn results

### Transform Tools
- **Align**: Align or arrange layers and other objects
- **Move**: Move layers, selections, and other objects
- **Crop**: Remove edge areas from image or layer
- **Rotate**: Rotate the layer, selection or path
- **Scale**: Scale the layer, selection or path
- **Shear**: Shear the layer, selection or path
- **Perspective**: Change perspective of the layer, selection or path
- **Flip**: Reverse the layer, selection or path horizontally or vertically
- **Cage Transform**: Deform a selection with a cage
- **Warp Transform**: Deform with different tools
- **Handle Transform**: Deform the layer, selection or path with handles
- **Unified Transform**: Transform the layer, selection or path
- **N-Point Deformation**: Deform the image using points
- **3D Transform**: Apply a 3D transformation
- **Offset**: Shift the content of the layer or selection

### Color Tools
- **Color Picker**: Pick colors from the image
- **Color Balance**: Adjust color distribution
- **Hue-Saturation**: Adjust hue, saturation and lightness
- **Colorize**: Colorize the image
- **Brightness-Contrast**: Adjust brightness and contrast
- **Threshold**: Reduce image to two colors using a threshold
- **Levels**: Adjust color levels
- **Curves**: Adjust color curves
- **Posterize**: Reduce number of colors
- **Desaturate**: Convert colors to grayscale

### Other Tools
- **Paths**: Create and edit paths
- **Text**: Create or edit text layers
- **Measure**: Measure distances and angles
- **Zoom**: Adjust the zoom level
- **Guide**: Add/Remove guides
- **Sample Point**: Add sample points
- **Gradient**: Draw a gradient

## Dialogs (`app/dialogs`)

- **About**: Information about GIMP
- **Action Search**: Search for actions
- **Channel Options**: Edit channel attributes
- **Color Profile**: Manage color profiles
- **Convert Indexed**: Convert image to indexed colors
- **Convert Precision**: Convert image precision
- **Dashboard**: Hardware resource usage
- **Data Delete**: Delete pattern/brush/etc
- **Extensions**: Manage extensions
- **File Open/Save**: Open and save files
- **Fill**: Fill options
- **Grid**: Configure image grid
- **Image Properties**: Image information
- **Image Scale**: Scale image
- **Input Devices**: Configure input devices
- **Keyboard Shortcuts**: Configure keyboard shortcuts
- **Layer Options**: Edit layer attributes
- **Module**: Module manager
- **Palette Import**: Import palette
- **Preferences**: GIMP Preferences
- **Print Size**: Set print resolution
- **Quit**: Quit GIMP
- **Resize**: Resize image/layer
- **Stroke**: Stroke selection/path
- **Tips**: User tips
- **Welcome**: Welcome screen

## Operations (`app/operations`)

- **Border**: Border selection
- **Brightness Contrast**
- **Color Balance**
- **Colorize**
- **Curves**
- **Desaturate**
- **Equalize**
- **Flood**
- **Gradient**
- **Grow**: Grow selection
- **Hue Saturation**
- **Levels**
- **Offset**
- **Posterize**
- **Profile Transform**
- **Semi Flatten**
- **Set Alpha**
- **Shrink**: Shrink selection
- **Threshold**
- **Threshold Alpha**

## Menus (`menus`)

Derived from menu UI files.
- **Image Menu**
- **Layers Menu**
- **Channels Menu**
- **Vectors (Paths) Menu**
- **Colormap Menu**
- **Dockable Menu**
- **Tools Menu**
- **Filters Menu**
- **Select Menu**
- **View Menu**
- **Windows Menu**
- **Help Menu**
