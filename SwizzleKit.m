
//  SwizzleKit
//  Created by Scott Morrison on 12/01/09.
//  ------------------------------------------------------------------------
//  Copyright (c) 2009, Scott Morrison All rights reserved.
//
//
//  ------------------------------------------------------------------------

#import "SwizzleKit.h"
#define SWIZZLE_PREFIX @"UNIQUE_PREFIX"
#define PROVIDER_SUFFIX @"UNIQUE_PREFIX"

@implementation NSObject (UNIQUE_PREFIXSwizzleKit)

-(BOOL)UNIQUE_PREFIXrespondsDirectlyToSelector:(SEL)aSelector{
	BOOL responds = NO;
	unsigned int methodCount = 0;
	Method * methods = nil;
	
	// extend instance Methods
	methods = class_copyMethodList([self class], &methodCount);
	int ci= methodCount;
	while (methods && ci--){
		if (method_getName(methods[ci]) == aSelector){
			responds = YES;
			break;
		}
	}
	free(methods);
	return responds;
}

@end


id UNIQUE_PREFIXobject_getMapTableVariable(id anObject, const char* variableName){
	static NSMapTable * mapTable = nil;
	if (!mapTable){
		if ([[anObject class] respondsToSelector:@selector(mapTable)]){
			mapTable  = [[anObject class] performSelector:@selector(mapTable)];
		}
	}
	id theValue = nil;
	if (mapTable){
		@synchronized(mapTable){
			NSMutableDictionary	*aDict;
			aDict = NSMapGet(mapTable, anObject);
			if (nil == aDict){
				aDict = [NSMutableDictionary dictionary];
				NSMapInsert(mapTable, anObject, aDict);
			}
			theValue = [aDict objectForKey:[NSString stringWithFormat:@"%s",variableName] ] ;
		}
	}
	return theValue;
}

void UNIQUE_PREFIXobject_setMapTableVariable(id anObject, const char* variableName,id value){
	static NSMapTable * mapTable = nil;
	if (!mapTable){
		if ([[anObject class] respondsToSelector:@selector(mapTable)]){
			mapTable  = [[anObject class] performSelector:@selector(mapTable)];
		}
	}
	if (mapTable){
		@synchronized(mapTable){
			NSMutableDictionary	*aDict;
			aDict = NSMapGet(mapTable, anObject);
			if (nil == aDict){
				aDict = [NSMutableDictionary dictionary];
				NSMapInsert(mapTable, anObject, aDict);
			}
			if (value){
				[aDict setObject:value forKey:[NSString stringWithFormat:@"%s",variableName]];
			}
			else{
				[aDict removeObjectForKey:[NSString stringWithFormat:@"%s",variableName]];
			}
		}
	}
	
}

void UNIQUE_PREFIXdescribeClass(const char * clsName){
	Class aClass = objc_getClass(clsName);
	if (aClass){
		NSMutableString * logString = [NSMutableString string];
		Class superClass = class_getSuperclass(aClass);
		const char * superClassName = class_getName(superClass);
		[logString appendFormat:@"@interface %s : %s\n{",clsName,superClassName];
		unsigned int ivarCount = 0;
		NSUInteger ci =0;
		Ivar * ivars = class_copyIvarList(aClass, &ivarCount);
		for (ci=0;ci<ivarCount;ci++){
			[logString appendFormat:@"    %s %s; //%ld\n",ivar_getTypeEncoding(ivars[ci]), ivar_getName(ivars[ci]), ivar_getOffset(ivars[ci])];
			
		}
		[logString appendString:@"}\n"];
		free(ivars);
		
		unsigned int classMethodCount =0;
		Method *classMethods = class_copyMethodList(object_getClass(aClass), &classMethodCount);
		for(ci=0;ci<classMethodCount;ci++){
			[logString appendFormat:@"+[%s %@]\n",class_getName(aClass),NSStringFromSelector(method_getName(classMethods[ci]))];
		}
		free(classMethods);
		
		unsigned int instanceMethodCount =0;
		Method *instanceMethods = class_copyMethodList(aClass, &instanceMethodCount);
		for(ci=0;ci<instanceMethodCount;ci++){
			[logString appendFormat:@"-[%s %@]\n",class_getName(aClass),NSStringFromSelector(method_getName(instanceMethods[ci]))];
		}
		
		
		
		NSLog(@"%@",logString);
	}
}

@implementation UNIQUE_PREFIXSwizzler
+(Class)subclass:(Class)baseClass usingClassName:(NSString*)subclassName providerClass:(Class)providerClass{
	Class subclass = objc_allocateClassPair(baseClass, [subclassName UTF8String], 0);
	if (!subclass) return nil;
	
	unsigned int ivarCount =0;
	Ivar * ivars = class_copyIvarList(providerClass, &ivarCount);
	unsigned int ci = 0;
	for (ci=0 ;ci < ivarCount; ci++){
		Ivar anIvar = ivars[ci];
		
		NSUInteger ivarSize = 0;
		NSUInteger ivarAlignment = 0;
		const char * typeEncoding = ivar_getTypeEncoding(anIvar);
		NSGetSizeAndAlignment(typeEncoding, &ivarSize, &ivarAlignment);
		const char * ivarName = ivar_getName(anIvar);
		BOOL addIVarResult = class_addIvar(subclass, ivarName, ivarSize, ivarAlignment, typeEncoding  );
		if (!addIVarResult){
			NSLog(@"could not add iVar %s", ivar_getName(anIvar));
			return nil;
		}
	
	}
	free(ivars);
	objc_registerClassPair(subclass);
	
	[self extendClass:subclass withMethodsFromClass:providerClass];
	return subclass;
}
+(void)extendClass:(Class) targetClass withMethodsFromClass:(Class)providerClass{
	unsigned int methodCount = 0;
	Method * methods = nil;
	
	// extend instance Methods
	methods = class_copyMethodList(providerClass, &methodCount);
	int ci= methodCount;
	while (methods && ci--){
		NSString * methodName = NSStringFromSelector(method_getName(methods[ci]));
		[self addInstanceMethodName:methodName fromProviderClass:providerClass toClass:targetClass];
		//NSLog(@"extending -[%s %@]",class_getName(targetClass),methodName);
	}
	free(methods);
	
	// extend Class Methods
	methods = class_copyMethodList(object_getClass(providerClass), &methodCount);
	ci= methodCount;
	while (methods && ci--){
		NSString * methodName = NSStringFromSelector(method_getName(methods[ci]));
		[self addClassMethodName:methodName fromProviderClass:providerClass toClass:targetClass];
		//NSLog(@"extending +[%s %@]",class_getName(targetClass),methodName);
	}
	free(methods);
	
	methods  = 0;
}

+(BOOL)addMethodName:(NSString *)methodName fromProviderClass:(Class)providerClass toClass:(Class)class isClassMethod:(BOOL)isClassMethod
{
	Class targetClass = class;
	if (isClassMethod) {
		targetClass = object_getClass(targetClass); // meta class
	}
	
	if (!targetClass) {
		return NO;
	}
	SEL selector = NSSelectorFromString(methodName);
	Method originalMethod = isClassMethod ? class_getClassMethod(providerClass,selector) : class_getInstanceMethod(providerClass,selector);
	
	if (!originalMethod) {
		return NO;
	}
	
	IMP originalImplementation = method_getImplementation(originalMethod);
	if (!originalImplementation) {
		return NO;
	}
	
	class_addMethod(targetClass, selector ,originalImplementation, method_getTypeEncoding(originalMethod));
	
	return YES;
}

+(BOOL)addClassMethodName:(NSString *)methodName fromProviderClass:(Class)providerClass toClass:(Class)targetClass
{
	return [self addMethodName:methodName fromProviderClass:providerClass toClass:targetClass isClassMethod:YES];
}

+(BOOL)addInstanceMethodName:(NSString *)methodName fromProviderClass:(Class)providerClass toClass:(Class)targetClass
{
	return [self addMethodName:methodName fromProviderClass:providerClass toClass:targetClass isClassMethod:NO];
}

+(IMP)swizzleMethod:(NSString*)methodName forClass:(Class)targetClass isClassMethod:(BOOL)isClassMethod
{
	NSString *kindSymbol = isClassMethod ? @"+" : @"-";
	Method (*class_getMethod)(Class cls, SEL name) = isClassMethod ? class_getClassMethod : class_getInstanceMethod;
	
	Method oldMethod, newMethod;
	SEL oldSelector = NSSelectorFromString(methodName);
	NSString * newMethodName = [SWIZZLE_PREFIX stringByAppendingString:methodName];
	SEL newSelector = NSSelectorFromString(newMethodName);
	
	oldMethod = class_getMethod(targetClass, oldSelector);
	if (oldMethod == NULL) {
		NSLog(@"SWIZZLE Error - Can't find existing method for %@[%@ %@]",kindSymbol,NSStringFromClass(targetClass),NSStringFromSelector(oldSelector));
		return NULL;
	}
	newMethod = class_getMethod(targetClass, newSelector);
	if (newMethod == NULL) {
		//look for a provider Class
		NSString * providerClassName = [NSStringFromClass(targetClass) stringByAppendingString:PROVIDER_SUFFIX];
		Class providerClass = NSClassFromString(providerClassName);
		if (providerClass) {
			BOOL methodAdded = [self addMethodName:newMethodName fromProviderClass:providerClass toClass:targetClass isClassMethod:isClassMethod];
			if (!methodAdded) {
				NSLog(@"SWIZZLE Error - Can't add %@%@ method to %@",kindSymbol,newMethodName,providerClassName);
				return NULL;
			}
			newMethod = class_getMethod(targetClass, newSelector);
			if (newMethod==NULL) {
				NSLog(@"SWIZZLE Error - Can't find method for %@[%@ %@]",kindSymbol,providerClassName,NSStringFromSelector(newSelector));
				return NULL;
			}
		}
		else {
			NSLog(@"SWIZZLE Error - Provider class not found (%@)",providerClassName);
			return NULL;
		}
	}
	
	if (NULL != oldMethod && NULL != newMethod) {
		IMP oldIMP = method_getImplementation(oldMethod);
		method_exchangeImplementations(oldMethod, newMethod);
		return oldIMP;
	}
	
	return NULL;
}

+(IMP)swizzleClassMethod:(NSString*)methodName forClass:(Class)targetClass
{
	return [self swizzleMethod:methodName forClass:targetClass isClassMethod:YES];
}

+(IMP)swizzleInstanceMethod:(NSString*)methodName forClass:(Class)targetClass
{
	return [self swizzleMethod:methodName forClass:targetClass isClassMethod:NO];
}

@end




@implementation NSThread(SwizzleKit)
+(NSArray*)abbreviatedCallStackSymbols{
	// returns the backtrace as a NSArray of NSStrings, simplifying the addresses etc in the process.
	void* callstack[128];
	int i, frames = backtrace(callstack, 128);
	char** strs = backtrace_symbols(callstack, frames);
	NSMutableArray *callStack = [[NSMutableArray alloc] initWithCapacity:frames];
	
	for (i = 1; i < frames; ++i) {
		NSString * frameString = [[NSString alloc] initWithUTF8String:strs[i]];
		NSScanner * scanner = [NSScanner scannerWithString:frameString];
		NSString * dummy = nil;
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * frameNumber = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&frameNumber];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * module = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&module];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * address = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&address];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * method = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&method];
		[callStack addObject:[NSString stringWithFormat:@"%3-s %18-s %@",[frameNumber UTF8String],[module UTF8String],method]];
		
	}
	free(strs);
	
	return [callStack autorelease];
}

+(NSArray *)callStackSymbolsForFrameCount:(NSInteger) frameCount{
	// will return the most recent <frameCount> stackFrames from the backtrace
	void* callstack[128];
	int i, frames = backtrace(callstack, 128);
	char** strs = backtrace_symbols(callstack, frames);
	NSMutableArray *callStack = [[NSMutableArray alloc] initWithCapacity:frames];
	int maxFrame = MIN(frames,frameCount+1);
	
	for (i = 1; i < maxFrame; ++i) {
		NSString * frameString = [[NSString alloc] initWithUTF8String:strs[i]];
		NSScanner * scanner = [NSScanner scannerWithString:frameString];
		NSString * dummy = nil;
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * frameNumber = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&frameNumber];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * module = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&module];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * address = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&address];
		[scanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString: &dummy];
		NSString * method = nil;
		[scanner scanUpToCharactersFromSet:[NSCharacterSet newlineCharacterSet] intoString:&method];
		[callStack addObject:[NSString stringWithFormat:@"%3-s %18-s %@",[frameNumber UTF8String],[module UTF8String],method]];
		
	}
	free(strs);
	
	return [callStack autorelease];
	
}
@end

