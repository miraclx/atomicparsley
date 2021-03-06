//==================================================================//
/*
    AtomicParsley - nsimage.mm

    AtomicParsley is GPL software; you can freely distribute,
    redistribute, modify & use under the terms of the GNU General
    Public License; either version 2 or its successor.

    AtomicParsley is distributed under the GPL "AS IS", without
    any warranty; without the implied warranty of merchantability
    or fitness for either an expressed or implied particular purpose.

    Please see the included GNU General Public License (GPL) for
    your rights and further details; see the file COPYING. If you
    cannot, write to the Free Software Foundation, 59 Temple Place
    Suite 330, Boston, MA 02111-1307, USA.  Or www.fsf.org

    Copyright �2005-2007 puck_lock
    with contributions from others; see the CREDITS file
                                                                   */
//==================================================================//

#include "AtomicParsley.h"
#import <Cocoa/Cocoa.h>

static void DetermineType(const char *picfilePath, bool &isJPEG, bool &isPNG) {
  char picHeader[20];

  FILE *pic_file = fopen(picfilePath, "rb");
  u_int64_t r = fread(picHeader, 8, 1, pic_file);
  fclose(pic_file);

  if (memcmp(picHeader, "\x89\x50\x4E\x47\x0D\x0A\x1A\x0A", 8) == 0) {
    isPNG = true;
    isJPEG = false;
  } else if (memcmp(picHeader, "\xFF\xD8\xFF", 3) == 0) {
    isJPEG = true;
    isPNG = false;
  } else {
    isPNG = false;
    isJPEG = false;
  }
}

static char *DeriveNewPath(const char *filePath,
                           PicPrefs myPicPrefs,
                           char *newpath,
                           size_t newpath_len) {
  const char *suffix = strrchr(filePath, '.');

  size_t filepath_len = strlen(filePath);
  memset(newpath, 0, newpath_len);
  size_t base_len = filepath_len - strlen(suffix);
  memcpy(newpath, filePath, base_len);
  memcpy(newpath + base_len, "-resized-", 9);

  char *randstring = (char *)calloc(1, sizeof(char) * 20);
  struct timeval tv;
  gettimeofday(&tv, NULL);

  srand((int)tv.tv_usec / 1000); // Seeds rand()
  int randNum = rand() % 10000;
  sprintf(randstring, "%i", randNum);
  strcat(newpath, randstring);

  if (myPicPrefs.allJPEG) {
    strcat(newpath, ".jpg");
  } else if (myPicPrefs.allPNG) {
    strcat(newpath, ".png");
  } else {
    strcat(newpath, suffix);
  }

  free(randstring);
  randstring = NULL;
  return newpath;
}

static NSImage *DoResize(NSImage *sourceImage, NSSize newSize) {
  if (!sourceImage.isValid) {
    return nil;
  }

  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes:NULL
                    pixelsWide:newSize.width
                    pixelsHigh:newSize.height
                 bitsPerSample:8
               samplesPerPixel:4
                      hasAlpha:YES
                      isPlanar:NO
                colorSpaceName:NSCalibratedRGBColorSpace
                   bytesPerRow:0
                  bitsPerPixel:0];
  rep.size = newSize;

  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext
      setCurrentContext:[NSGraphicsContext
                            graphicsContextWithBitmapImageRep:rep]];
  [sourceImage drawInRect:NSMakeRect(0, 0, newSize.width, newSize.height)
                 fromRect:NSZeroRect
                operation:NSCompositingOperationCopy
                 fraction:1.0];
  [NSGraphicsContext restoreGraphicsState];

  NSImage *newImage = [[NSImage alloc] initWithSize:newSize];
  [newImage addRepresentation:rep];
  return newImage;
}

bool ResizeGivenImage(const char *filePath,
                      PicPrefs myPicPrefs,
                      char *resized_path,
                      size_t resized_path_len) {
  bool resize = false;

  NSImage *source = [[NSImage alloc]
      initWithContentsOfFile:[NSString stringWithUTF8String:filePath]];
  if (source == nil) {
    fprintf(stderr, "Image '%s' could not be loaded.\n", filePath);
    exit(1);
  }

  NSSize sourceSize = [source size];
  float hmax, vmax, aspect;
  hmax = sourceSize.width;
  vmax = sourceSize.height;
  aspect = sourceSize.height / sourceSize.width;
  // fprintf(stdout, "aspect %f2.4\n", aspect);
  if (myPicPrefs.max_dimension != 0) {
    if (((int)sourceSize.width > myPicPrefs.max_dimension) ||
        ((int)sourceSize.height > myPicPrefs.max_dimension)) {
      resize = true; // only if dimensions are LARGER than our max do we resize
      if (hmax > vmax) {
        hmax = myPicPrefs.max_dimension;
        vmax = myPicPrefs.max_dimension * aspect;
      } else {
        hmax = myPicPrefs.max_dimension / aspect;
        vmax = myPicPrefs.max_dimension;
      }
    }
  }

  ///// determine dpi/ppi
  float hres, vres, hdpi, vdpi;
  NSImageRep *myRep = [[source representations] objectAtIndex:0];
  hres = [myRep pixelsWide]; // native pixel dimensions
  vres = [myRep pixelsHigh];
  hdpi = hres /
         sourceSize
             .width; // in native resolution (multiply by 72 to get native dpi)
  vdpi = vres / sourceSize.height;

  if (((int)hdpi != 1) || ((int)vdpi != 1)) {
    resize = true;
    hmax = hres;
    vmax = vres;
    if (myPicPrefs.max_dimension != 0) {
      // we also need to recheck we don't go over our max dimensions (again)
      if (((int)hres > myPicPrefs.max_dimension) ||
          ((int)vres > myPicPrefs.max_dimension)) {
        if (hmax > vmax) {
          hmax = myPicPrefs.max_dimension;
          vmax = myPicPrefs.max_dimension * aspect;
        } else {
          hmax = myPicPrefs.max_dimension / aspect;
          vmax = myPicPrefs.max_dimension;
        }
      }
    }
  }

  if (myPicPrefs.squareUp) {
    if (myPicPrefs.max_dimension != 0) {
      vmax = myPicPrefs.max_dimension;
      hmax = myPicPrefs.max_dimension;
      resize = true;
    } else {
      // this will stretch the image to the largest dimension. Hope you don't
      // try to scale a 160x1200 image... it could get ugly
      if (hmax > vmax) {
        vmax = hmax;
        resize = true;
      } else if (vmax > hmax) {
        hmax = vmax;
        resize = true;
      }
    }
  }

  if (myPicPrefs.force_dimensions) {
    if (myPicPrefs.force_height > 0 && myPicPrefs.force_width > 0) {
      vmax = myPicPrefs.force_height;
      hmax = myPicPrefs.force_width;
      resize = true;
    }
  }

  uint64_t pic_file_size = findFileSize(filePath);
  if (((int)pic_file_size > myPicPrefs.max_Kbytes) &&
      (myPicPrefs.max_Kbytes != 0)) {
    resize = true;
  }

  bool isJPEG, isPNG;
  DetermineType(filePath, isJPEG, isPNG);
  if ((isJPEG && myPicPrefs.allPNG) ||
      (isPNG && myPicPrefs.allJPEG)) { // handle jpeg->png & png->jpg conversion
    resize = true;
  }

  NSRect destinationRect = NSMakeRect(0, 0, hmax, vmax);
  NSSize size = NSMakeSize(hmax, vmax);

  if (resize) {
    NSImage *image = DoResize(source, size);

    NSData *imageData = [image TIFFRepresentation];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:imageData];

    NSBitmapImageFileType filetype;
    NSDictionary *props;

    if ((isPNG && !myPicPrefs.allJPEG) || myPicPrefs.allPNG) {
      filetype = NSBitmapImageFileTypePNG;
      props = nil;
    } else {
      filetype = NSBitmapImageFileTypeJPEG;
      props = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:0.7]
                                          forKey:NSImageCompressionFactor];
    }
    NSData *data = [bitmap representationUsingType:filetype properties:props];
    unsigned dataLength = [data length]; // holds the file length

    int iter = 0;
    float compression = 0.65;
    if ((myPicPrefs.max_Kbytes != 0) &&
        (filetype == NSBitmapImageFileTypeJPEG)) {
      while ((dataLength > (unsigned)myPicPrefs.max_Kbytes) && (iter < 10)) {
        props = [NSDictionary
            dictionaryWithObject:[NSNumber numberWithFloat:compression]
                          forKey:NSImageCompressionFactor];
        data = [bitmap representationUsingType:filetype properties:props];
        dataLength = [data length];
        compression = compression - 0.05;
        iter++;
      }
    }

    NSString *outFile =
        [NSString stringWithUTF8String:DeriveNewPath(filePath,
                                                     myPicPrefs,
                                                     resized_path,
                                                     resized_path_len)];
    [[NSFileManager defaultManager] createFileAtPath:outFile
                                            contents:data
                                          attributes:nil];

    [image release];
    [bitmap release];
    memcpy(resized_path,
           [outFile cStringUsingEncoding:NSUTF8StringEncoding],
           [outFile lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
  }
  [source release];
  return resize;
}
