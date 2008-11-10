#import "ViDocument.h"
#import "ExTextView.h"
#import "ViLanguageStore.h"

#import "NoodleLineNumberView.h"
#import "NoodleLineNumberMarker.h"
#import "MarkerLineNumberView.h"

BOOL makeNewWindowInsteadOfTab = NO;

@interface ViDocument (internal)
- (ViWindowController *)windowController;
@end

@implementation ViDocument

- (id)init
{
	self = [super init];
	return self;
}

#pragma mark -
#pragma mark NSDocument interface

- (NSString *)windowNibName
{
	return @"ViDocument";
}

- (void)makeWindowControllers
{
	if (makeNewWindowInsteadOfTab)
	{
		windowController = [[ViWindowController alloc] init];
		makeNewWindowInsteadOfTab = NO;
	}
	else
	{
		windowController = [ViWindowController currentWindowController];
	}

	[self addWindowController:windowController];
	[windowController addNewTab:self];
}

- (void)configureSyntax
{
	/* update syntax definition */
	NSDictionary *syntaxOverride = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"syntaxOverride"];
	NSString *syntax = [syntaxOverride objectForKey:[[self fileURL] path]];
	if (syntax)
		[textView setLanguage:syntax];
	else
		[textView configureForURL:[self fileURL]];
	[languageButton selectItemWithTitle:[[textView language] displayName]];
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
	[super windowControllerDidLoadNib:aController];
	[textView initEditorWithDelegate:self];

	[textView setString:readContent];
	[self configureSyntax];

	[statusbar setFont:[NSFont controlContentFontOfSize:11.0]];

	[symbolsButton removeAllItems];
	[symbolsButton addItemWithTitle:@"not implemented"];
	[symbolsButton setEnabled:NO];
	[symbolsButton setFont:[NSFont controlContentFontOfSize:11.0]];

	[languageButton removeAllItems];
	[languageButton addItemsWithTitles:[[[ViLanguageStore defaultStore] allLanguageNames] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]];
	[languageButton selectItemWithTitle:[[textView language] displayName]];
	[languageButton setFont:[NSFont controlContentFontOfSize:11.0]];

	lineNumberView = [[MarkerLineNumberView alloc] initWithScrollView:scrollView];
	[scrollView setVerticalRulerView:lineNumberView];
	[scrollView setHasHorizontalRuler:NO];
	[scrollView setHasVerticalRuler:YES];
	[scrollView setRulersVisible:YES];
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
	return [[[textView textStorage] string] dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	readContent = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	return YES;
}

- (void)setFileURL:(NSURL *)absoluteURL
{
	[super setFileURL:absoluteURL];
	[self configureSyntax];
}

#pragma mark -
#pragma mark Other stuff

- (NSView *)view
{
	return view;
}

- (void)changeTheme:(ViTheme *)theme
{
	[textView setTheme:theme];
}

- (void)setPageGuide:(int)pageGuideValue
{
	[textView setPageGuide:pageGuideValue];
}

#pragma mark -
#pragma mark ViTextView delegate methods

- (void)message:(NSString *)fmt, ...
{
	va_list ap;
	va_start(ap, fmt);
	NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
	va_end(ap);

	[statusbar setStringValue:msg];
}

- (IBAction)finishedExCommand:(id)sender
{
	NSString *exCommand = [statusbar stringValue];
	[statusbar setStringValue:@""];
	[statusbar setEditable:NO];
	[[[self windowController] window] makeFirstResponder:textView];
	if ([exCommand length] > 0)
		[textView performSelector:exCommandSelector withObject:exCommand];
}

- (void)getExCommandForTextView:(ViTextView *)aTextView selector:(SEL)aSelector prompt:(NSString *)aPrompt
{
	[statusbar setStringValue:aPrompt];
	[statusbar setEditable:YES];
	[statusbar setDelegate:self];
	exCommandSelector = aSelector;
	[[[self windowController] window] makeFirstResponder:statusbar];
}

- (void)getExCommandForTextView:(ViTextView *)aTextView selector:(SEL)aSelector
{
	[self getExCommandForTextView:aTextView selector:aSelector prompt:@":"];
}

- (BOOL)findPattern:(NSString *)pattern
	    options:(unsigned)find_options
         regexpType:(OgreSyntax)regexpSyntax
   ignoreLastRegexp:(BOOL)ignoreLastRegexp
{
	return [textView findPattern:pattern options:find_options regexpType:regexpSyntax ignoreLastRegexp:ignoreLastRegexp];
}

// tag push
- (void)pushLine:(NSUInteger)aLine column:(NSUInteger)aColumn
{
	[[[self windowController] sharedTagStack] pushFile:[[self fileURL] path] line:aLine column:aColumn];
}

- (void)popTag
{
	NSDictionary *location = [[[self windowController] sharedTagStack] pop];
	if (location == nil)
	{
		[self message:@"The tags stack is empty"];
		return;
	}

	NSString *file = [location objectForKey:@"file"];
	ViDocument *document = [[NSDocumentController sharedDocumentController]
		openDocumentWithContentsOfURL:[NSURL fileURLWithPath:file] display:YES error:nil];

	if (document)
	{
		[[self windowController] selectDocument:document];
		[[document textView] gotoLine:[[location objectForKey:@"line"] unsignedIntegerValue]
				       column:[[location objectForKey:@"column"] unsignedIntegerValue]];
	}
}

#pragma mark -

- (ViTextView *)textView
{
	return textView;
}

- (ViWindowController *)windowController
{
	return [[self windowControllers] objectAtIndex:0];
}

- (void)close
{
	[self removeWindowController:windowController];
	[super close];
}

#if 0
- (void)shouldCloseWindowController:(NSWindowController *)aWindowController
                           delegate:(id)aDelegate
	        shouldCloseSelector:(SEL)shouldCloseSelector
			contextInfo:(void *)contextInfo
{
	[super shouldCloseWindowController:aWindowController delegate:aDelegate shouldCloseSelector:shouldCloseSelector contextInfo:contextInfo];
}
#endif

- (void)canCloseDocumentWithDelegate:(id)aDelegate shouldCloseSelector:(SEL)shouldCloseSelector contextInfo:(void *)contextInfo
{
	[super canCloseDocumentWithDelegate:self shouldCloseSelector:@selector(document:shouldClose:contextInfo:) contextInfo:contextInfo];
}

- (void)document:(NSDocument *)doc shouldClose:(BOOL)shouldClose contextInfo:(void *)contextInfo
{
	if (shouldClose)
	{
		[windowController removeTabViewItemContainingDocument:self];
		[self close];
		if ([windowController numberOfTabViewItems] == 0)
		{
			/* Close the window after all tabs are gone. */
			[[windowController window] performClose:self];
		}
	}
}

- (IBAction)setLanguage:(id)sender
{
	[textView setLanguage:[sender title]];
	ViLanguage *lang = [textView language];
	if (lang)
	{
		NSMutableDictionary *syntaxOverride = [NSMutableDictionary dictionaryWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"syntaxOverride"]];
		[syntaxOverride setObject:[sender title] forKey:[[self fileURL] path]];
		[[NSUserDefaults standardUserDefaults] setObject:syntaxOverride forKey:@"syntaxOverride"];
	}
}

@end
