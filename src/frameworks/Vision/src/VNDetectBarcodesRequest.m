/*
 This file is part of Darling.

 Copyright (C) 2019 Lubos Dolezel

 Darling is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 Darling is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with Darling.  If not, see <http://www.gnu.org/licenses/>.
*/

#import <Vision/VNDetectBarcodesRequest.h>

VNBarcodeSymbology const VNBarcodeSymbologyAztec = @"org.iso.Aztec";
VNBarcodeSymbology const VNBarcodeSymbologyCode128 = @"org.iso.Code128";
VNBarcodeSymbology const VNBarcodeSymbologyCode39 = @"org.iso.Code39";
VNBarcodeSymbology const VNBarcodeSymbologyCode39Checksum = @"org.iso.Code39Checksum";
VNBarcodeSymbology const VNBarcodeSymbologyCode39FullASCII = @"org.iso.Code39FullASCII";
VNBarcodeSymbology const VNBarcodeSymbologyCode39FullASCIIChecksum = @"org.iso.Code39FullASCIIChecksum";
VNBarcodeSymbology const VNBarcodeSymbologyCode93 = @"org.iso.Code93";
VNBarcodeSymbology const VNBarcodeSymbologyCode93i = @"org.iso.Code93i";
VNBarcodeSymbology const VNBarcodeSymbologyDataMatrix = @"org.iso.DataMatrix";
VNBarcodeSymbology const VNBarcodeSymbologyEAN13 = @"org.gs1.EAN-13";
VNBarcodeSymbology const VNBarcodeSymbologyEAN8 = @"org.gs1.EAN-8";
VNBarcodeSymbology const VNBarcodeSymbologyI2of5 = @"org.iso.I2of5";
VNBarcodeSymbology const VNBarcodeSymbologyI2of5Checksum = @"org.iso.I2of5Checksum";
VNBarcodeSymbology const VNBarcodeSymbologyITF14 = @"org.iso.ITF14";
VNBarcodeSymbology const VNBarcodeSymbologyPDF417 = @"org.iso.PDF417";
VNBarcodeSymbology const VNBarcodeSymbologyQR = @"org.iso.QRCode";
VNBarcodeSymbology const VNBarcodeSymbologyUPCE = @"org.gs1.UPC-E";

@implementation VNDetectBarcodesRequest

- (NSMethodSignature *)methodSignatureForSelector:(SEL)aSelector
{
    return [NSMethodSignature signatureWithObjCTypes: "v@:"];
}

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
    NSLog(@"Stub called: %@ in %@", NSStringFromSelector([anInvocation selector]), [self class]);
}

@end
