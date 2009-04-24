/*

Preferences.m ... Pref Bundle for GriP
 
Copyright (c) 2009, KennyTM~
All rights reserved.
 
Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, 
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
 * Neither the name of the KennyTM~ nor the names of its contributors may be
   used to endorse or promote products derived from this software without
   specific prior written permission.
 
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
*/

#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Foundation/Foundation.h>
#import <GriP/Duplex/Client.h>
#import <GriP/common.h>
#import <UIKit/UIKit.h>
#import <GriP/GrowlApplicationBridge.h>
#import <GriP/GPApplicationBridge.h>
#include <notify.h>

#define PREFDICT @"/Library/GriP/Preferences.plist"

static GPApplicationBridge* bridge = nil;

#define LS(str) [myBundle localizedStringForKey:str value:nil table:nil]

//------------------------------------------------------------------------------
#pragma mark -

@interface ExtensionsController : PSListController {
	NSMutableDictionary* enabled;
	NSMutableSet* modifedExtensions;
}
-(id)initForContentSize:(CGSize)size;
-(void)dealloc;
-(NSArray*)specifiers;
-(NSNumber*)getEnabled:(PSSpecifier*)spec;
-(void)set:(NSNumber*)val enabled:(PSSpecifier*)spec;
@end
@implementation ExtensionsController
-(id)initForContentSize:(CGSize)size {
	if ((self = [super initForContentSize:size])) {
		enabled = [[NSMutableDictionary alloc] init];
		modifedExtensions = [[NSMutableSet alloc] init];
		NSFileManager* man = [NSFileManager defaultManager];
		NSNumber* y = [NSNumber numberWithBool:YES];
		for (NSString* subpath in [man contentsOfDirectoryAtPath:@"/Library/GriP/Extensions/" error:NULL]) {
			if ([subpath hasSuffix:@".gripext"])
				[enabled setObject:y forKey:subpath];
		}
		y = [NSNumber numberWithBool:NO];
		for (NSString* disabled in [[NSDictionary dictionaryWithContentsOfFile:PREFDICT] objectForKey:@"DisabledExtensions"])
			[enabled setObject:y forKey:disabled];
	}
	return self;
}
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		NSMutableArray* _s = [[NSMutableArray alloc] initWithObjects:[PSSpecifier emptyGroupSpecifier], nil];
		[[NSFileManager defaultManager] changeCurrentDirectoryPath:@"/Library/GriP/Extensions/"];
		PSSpecifier* spec;
		
		for (NSString* subpath in enabled) {
			NSBundle* bundle = [NSBundle bundleWithPath:subpath];
			NSString* friendlyName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [subpath stringByDeletingPathExtension];
			spec = [PSSpecifier preferenceSpecifierNamed:friendlyName target:self set:@selector(set:enabled:) get:@selector(getEnabled:) detail:nil cell:PSSwitchCell edit:nil];
			[spec setProperty:subpath forKey:@"id"];
			NSString* iconPath = [bundle pathForResource:@"icon" ofType:@"png"];
			if (iconPath != nil)
				[spec setupIconImageWithPath:iconPath];
			[_s addObject:spec];
		}
		_specifiers = _s;
	}
	return _specifiers;
}
-(NSNumber*)getEnabled:(PSSpecifier*)spec { return [enabled objectForKey:spec.identifier]; }
-(void)set:(NSNumber*)val enabled:(PSSpecifier*)spec {
	NSString* subpath = spec.identifier;
	[enabled setObject:val forKey:subpath];
	[modifedExtensions addObject:subpath];
}
-(void)dealloc {
	NSMutableDictionary* prefs = [NSMutableDictionary dictionaryWithContentsOfFile:PREFDICT];
	[prefs setObject:[enabled allKeysForObject:[NSNumber numberWithBool:NO]] forKey:@"DisabledExtensions"];
	[prefs writeToFile:PREFDICT atomically:NO];
	
	[enabled release];
	
	if ([modifedExtensions count] != 0) {
		[GPDuplexClient sendMessage:GriPMessage_FlushPreferences data:nil expectsReturn:YES];	// use this to force the method to wait until done.
		[GPDuplexClient sendMessage:GriPMessage_ReloadExtensions data:[NSPropertyListSerialization dataFromPropertyList:[modifedExtensions allObjects]
																												 format:NSPropertyListBinaryFormat_v1_0
																									   errorDescription:NULL]];
	}
	[modifedExtensions release];
	
	[super dealloc];
}
@end

//------------------------------------------------------------------------------
#pragma mark -

@interface BackgroundColorsController : PSListController {}
@end
@implementation BackgroundColorsController
@end

__attribute__((visibility("hidden")))
@interface MessageController : PSListController {
	NSMutableDictionary* msgdict;
}
-(NSArray*)specifiers;
-(NSObject*)getMessage:(PSSpecifier*)spec;
@end
@implementation MessageController
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"Message" target:self] retain];
		PSSpecifier* spec = self.specifier;
		msgdict = [spec propertyForKey:@"msgdict"];
		[self specifierForID:@"description"].name = [msgdict objectForKey:@"description"];
		self.title = spec.name;
	}
	return _specifiers;
}
-(NSObject*)getMessage:(PSSpecifier*)spec { return [msgdict objectForKey:spec.identifier] ?: [NSNumber numberWithInteger:0]; }
-(void)set:(NSObject*)obj message:(PSSpecifier*)spec { [msgdict setObject:obj forKey:spec.identifier]; }
@end

//------------------------------------------------------------------------------
#pragma mark -

__attribute__((visibility("hidden")))
@interface TicketController : PSListController {
	NSMutableDictionary* dict;
}
-(NSArray*)specifiers;
-(void)dealloc;
-(NSObject*)getTicket:(PSSpecifier*)spec;
-(void)set:(NSObject*)obj ticket:(PSSpecifier*)spec;
@end

@implementation TicketController
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		PSSpecifier* mySpec = self.specifier;
		
		NSString* filename = [mySpec propertyForKey:@"fn"];
		NSError* error = nil;
		NSData* data = [[NSData alloc] initWithContentsOfFile:filename options:0 error:&error];
		NSString* errDesc = [error localizedDescription];
		
		if (data != nil) {
			dict = [[NSPropertyListSerialization propertyListFromData:data mutabilityOption:kCFPropertyListMutableContainersAndLeaves format:NULL errorDescription:&errDesc] retain];
			[errDesc autorelease];
			[data release];
		}
		
		if (dict != nil) {
			_specifiers = [[self loadSpecifiersFromPlistName:@"Ticket" target:self] retain];
			NSMutableArray* secondPart = [[NSMutableArray alloc] init];
			
			NSMutableDictionary* messagesDict = [dict objectForKey:@"messages"];
			for (NSString* key in [[messagesDict allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
				NSMutableDictionary* msg = [messagesDict objectForKey:key];
				NSString* name = [msg objectForKey:@"friendlyName"] ?: key;
				PSSpecifier* spec = [PSSpecifier preferenceSpecifierNamed:name target:nil set:nil get:nil detail:[MessageController class] cell:PSLinkCell edit:Nil];
				[spec setProperty:msg forKey:@"msgdict"];
				[secondPart addObject:spec];
			}
			[self insertContiguousSpecifiers:secondPart afterSpecifierID:@"_msgList"];
			[secondPart release];
			
		} else {
			_specifiers = [[NSArray alloc] initWithObjects:[PSSpecifier groupSpecifierWithName:errDesc], nil];
		}
		
		self.title = mySpec.name;
	}
	return _specifiers;
}
-(void)dealloc {
	[dict writeToFile:[self.specifier propertyForKey:@"fn"] atomically:NO];
	[dict release];
	[super dealloc];
}
-(NSObject*)getTicket:(PSSpecifier*)spec {
	return [dict objectForKey:spec.identifier] ?: [NSNumber numberWithInteger:0];
}
-(void)set:(NSObject*)obj ticket:(PSSpecifier*)spec {
	[dict setObject:obj forKey:spec.identifier];
}
-(void)removeSettings {
	PSSpecifier* mySpec = self.specifier;
	NSError* err = nil;
	NSString* path = [mySpec propertyForKey:@"fn"];
	BOOL success = [[NSFileManager defaultManager] removeItemAtPath:path error:&err];
	if (!success) {
		NSBundle* myBundle = self.bundle;
		[bridge notifyWithTitle:[NSString stringWithFormat:LS(@"Cannot remove settings for %@"), mySpec.name]
					description:[NSString stringWithFormat:LS(@"Error: %@<br/><br/>Please delete <code>%@</code> manually."), err, path]
			   notificationName:@"Cannot remove settings"
					   iconData:@"com.apple.Preferences"
					   priority:0
					   isSticky:NO
				   clickContext:nil];
		[err release];
	} else {
		PSListController* ctrler = [self parentController];
		[dict release];
		dict = nil;
		[ctrler removeSpecifier:mySpec];
		[ctrler popController];
	}
}
@end

//------------------------------------------------------------------------------
#pragma mark -

@interface GPPrefsListController : PSListController<GrowlApplicationBridgeDelegate> {}
-(id)initForContentSize:(CGSize)size;
-(void)dealloc;
-(NSArray*)specifiers;
-(NSObject*)get:(PSSpecifier*)spec;
-(void)set:(NSObject*)obj with:(PSSpecifier*)spec;
-(void)updateColor:(NSArray*)colorArray atIndex:(int)x;
-(void)preview;

-(NSDictionary*)registrationDictionaryForGrowl;
-(NSString*)applicationNameForGrowl;
-(void)growlNotificationWasClicked:(NSObject*)context;
-(void)growlNotificationTimedOut:(NSObject*)context;
@end
@implementation GPPrefsListController
-(id)initForContentSize:(CGSize)size {
	if ((self = [super initForContentSize:size])) {
		bridge = [[GPApplicationBridge alloc] init];
		bridge.growlDelegate = self;
	}
	return self;
}
-(void)dealloc {
	[bridge release];
	[super dealloc];
}
-(NSArray*)specifiers {
	if (_specifiers == nil) {
		_specifiers = [[self loadSpecifiersFromPlistName:@"GriP" target:self] retain];
		NSMutableArray* secondPart = [[NSMutableArray alloc] init];
		// populate the per-app settings.
		for (NSString* filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:@"/Library/GriP/Tickets/" error:NULL]) {
			if ([filename hasSuffix:@".ticket"]) {
				PSSpecifier* spec = [PSSpecifier preferenceSpecifierNamed:[filename stringByDeletingPathExtension] target:nil set:nil get:nil detail:[TicketController class] cell:PSLinkCell edit:Nil];
				[spec setProperty:[@"/Library/GriP/Tickets/" stringByAppendingPathComponent:filename] forKey:@"fn"];
				[secondPart addObject:spec];
			}
		}
		[self addSpecifiersFromArray:secondPart];
		[secondPart release];
	}
	return _specifiers;
}
-(NSObject*)get:(PSSpecifier*)spec {
	return [[NSDictionary dictionaryWithContentsOfFile:PREFDICT] objectForKey:spec.identifier];
}
-(void)set:(NSObject*)obj with:(PSSpecifier*)spec {
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithContentsOfFile:PREFDICT];
	[dict setObject:obj forKey:spec.identifier];
	[dict writeToFile:PREFDICT atomically:NO];
	[GPDuplexClient sendMessage:GriPMessage_FlushPreferences data:nil];
}

-(void)updateColor:(NSArray*)colorArray atIndex:(int)x {
	UIView* cell = [[self lastController] cachedCellForSpecifierID:[NSString stringWithFormat:@"x%d", x]];
	UIView* previewBox = [cell.subviews lastObject];
	BOOL newPreviousBox = previewBox.tag != 42;
	if (newPreviousBox)
		previewBox = [[UIView alloc] initWithFrame:CGRectMake(280, 20, 30, 15)];
	
	previewBox.backgroundColor = [UIColor colorWithRed:[[colorArray objectAtIndex:0] floatValue]
												 green:[[colorArray objectAtIndex:1] floatValue]
												  blue:[[colorArray objectAtIndex:2] floatValue] alpha:1];
	previewBox.tag = 42;
	
	if (newPreviousBox) {
		[cell addSubview:previewBox];
		[previewBox release];
	}
	
}
-(NSNumber*)getComponent:(PSSpecifier*)spec {
	int val = [spec.identifier integerValue];
	int j = 4-val/3;
	NSArray* color = [[[NSDictionary dictionaryWithContentsOfFile:PREFDICT] objectForKey:@"BackgroundColors"] objectAtIndex:j];
	[self updateColor:color atIndex:j];
	return [color objectAtIndex:(val%3)];
}
-(void)set:(NSNumber*)obj forComponent:(PSSpecifier*)spec {
	int val = [spec.identifier integerValue];
	NSMutableDictionary* dict = [NSMutableDictionary dictionaryWithContentsOfFile:PREFDICT];
	int j = 4-val/3;
	NSMutableArray* color = [[dict objectForKey:@"BackgroundColors"] objectAtIndex:j];
	[color replaceObjectAtIndex:(val%3) withObject:obj];
	[self updateColor:color atIndex:j];
	[dict writeToFile:PREFDICT atomically:NO];
	[GPDuplexClient sendMessage:GriPMessage_FlushPreferences data:nil];
}
-(void)preview {
	NSBundle* myBundle = self.bundle;
	[bridge notifyWithTitle:LS(@"GriP Message Preview")
				description:LS(@"This is a preview of a normal <strong>GriP</strong> message.")
		   notificationName:@"Preview"
				   iconData:@"com.apple.Preferences"
				   priority:0
				   isSticky:NO
			   clickContext:@"r"];
}

//------------------------------------------------------------------------------
#pragma mark -

-(NSDictionary*)registrationDictionaryForGrowl {
	NSArray* allNotifs = [NSArray arrayWithObjects:@"Preview", @"Message touched", @"Message ignored", @"Cannot remove settings", nil];
	return [NSDictionary dictionaryWithObjectsAndKeys:
			allNotifs, GROWL_NOTIFICATIONS_ALL,
			allNotifs, GROWL_NOTIFICATIONS_DEFAULT,
			[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Preview a GriP message.", @"Touched the preview message.", @"Ignored or closed the preview message.", @"Per-app settings cannot be removed.", nil]
										forKeys:allNotifs], GROWL_NOTIFICATIONS_DESCRIPTIONS,
			nil];
}
-(NSString*)applicationNameForGrowl { return @"GriP Preferences"; }
-(void)growlNotificationWasClicked:(NSObject*)context {
	if ([@"r" isEqualToString:(NSString*)context]) {
		NSBundle* myBundle = self.bundle;
		[bridge notifyWithTitle:LS(@"Message touched")
					description:LS(@"You have touched the GriP preview message.")
			   notificationName:@"Message touched"
					   iconData:@"com.apple.Preferences"
					   priority:1
					   isSticky:NO
				   clickContext:@""];
	}
}
-(void)growlNotificationTimedOut:(NSObject*)context {
	if ([@"r" isEqualToString:(NSString*)context]) {
		NSBundle* myBundle = self.bundle;
		[bridge notifyWithTitle:LS(@"Message ignored")
					description:LS(@"You have closed or ignored the GriP preview message.")
			   notificationName:@"Message touched"
					   iconData:@"com.apple.Preferences"
					   priority:-1
					   isSticky:NO
				   clickContext:@""];
	}
}
@end

//------------------------------------------------------------------------------
#pragma mark -

