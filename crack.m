#import "crack.h"
#import <Foundation/Foundation.h>
#import "NSTask.h"
#import "ZipArchive.h"
#include <sys/stat.h>

#define Z_NO_COMPRESSION         0
#define Z_BEST_SPEED             1
#define Z_BEST_COMPRESSION       9
#define Z_DEFAULT_COMPRESSION  (-1)

int overdrive_enabled = 0;
int only_armv7 = 0;
int only_armv6 = 0;
int bash = 0;

int compression_level = -1;


long fsize(const char *file) {
    struct stat st;
    if (stat(file, &st) == 0)
        return st.st_size;
    
    return -1; 
}
ZipArchive * createZip(NSString *file) {
    ZipArchive *archiver = [[ZipArchive alloc] init];
    [archiver CreateZipFile2:file];
    return archiver;
}
void zip(ZipArchive *archiver, NSString *folder) {
    BOOL isDir=NO;	
    NSArray *subpaths;	
    int total = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];	
    if ([fileManager fileExistsAtPath:folder isDirectory:&isDir] && isDir){
        subpaths = [fileManager subpathsAtPath:folder];
        total = [subpaths count];
    }
    int togo = total;
    
    
    for(NSString *path in subpaths){
		togo--;
        PERCENT((int)ceil((((double)total - togo) / (double)total) * 100));
        // Only add it if it's not a directory. ZipArchive will take care of those.
        NSString *longPath = [folder stringByAppendingPathComponent:path];
        if([fileManager fileExistsAtPath:longPath isDirectory:&isDir] && !isDir){
            [archiver addFileToZip:longPath newname:path compression:compression_level];	
        }
    }
    return;
}

void zip_original(ZipArchive *archiver, NSString *folder, NSString *binary, NSString* zip) {
    long size;
    BOOL isDir=NO;	
    NSArray *subpaths;	
    int total = 0;
    NSFileManager *fileManager = [NSFileManager defaultManager];	
    if ([fileManager fileExistsAtPath:folder isDirectory:&isDir] && isDir){
        subpaths = [fileManager subpathsAtPath:folder];
        total = [subpaths count];
    }
    int togo = total;
    
    
    for(NSString *path in subpaths) {
		togo--;
        if (([path rangeOfString:@".app"].location != NSNotFound) && ([path rangeOfString:@"SC_Info"].location == NSNotFound) && ([path rangeOfString:@"Library"].location == NSNotFound) && ([path rangeOfString:@"tmp"].location == NSNotFound) && ([path rangeOfString:[NSString stringWithFormat:@".app/%@", binary]].location == NSNotFound)) {
            PERCENT((int)ceil((((double)total - togo) / (double)total) * 100));
            // Only add it if it's not a directory. ZipArchive will take care of those.
            NSString *longPath = [folder stringByAppendingPathComponent:path];
            if([fileManager fileExistsAtPath:longPath isDirectory:&isDir] && !isDir){
                size += fsize([longPath UTF8String]);
                if (size > 31457280){
                    VERBOSE("Zip went over 30MB, saving..");
                    [archiver CloseZipFile2];
                    [archiver release];
                    archiver = [[ZipArchive alloc] init];
                    [archiver openZipFile2:zip];
                }
                [archiver addFileToZip:longPath newname:[NSString stringWithFormat:@"Payload/%@", path] compression:compression_level];
            }
        }
    }
    return;
}

NSString * crack_application(NSString *application_basedir, NSString *basename, NSString *version) {
    VERBOSE("Creating working directory...");
	NSString *workingDir = [NSString stringWithFormat:@"%@%@/", @"/tmp/clutch_", genRandStringLength(8)];
	if (![[NSFileManager defaultManager] createDirectoryAtPath:[workingDir stringByAppendingFormat:@"Payload/%@", basename] withIntermediateDirectories:YES attributes:[NSDictionary
			dictionaryWithObjects:[NSArray arrayWithObjects:@"mobile", @"mobile", nil]
			forKeys:[NSArray arrayWithObjects:@"NSFileOwnerAccountName", @"NSFileGroupOwnerAccountName", nil]
			] error:NULL]) {
		printf("error: Could not create working directory\n");
		return nil;
	}
	
    VERBOSE("Performing initial analysis...");
	struct stat statbuf_info;
	stat([[application_basedir stringByAppendingString:@"Info.plist"] UTF8String], &statbuf_info);
	time_t ist_atime = statbuf_info.st_atime;
	time_t ist_mtime = statbuf_info.st_mtime;
	struct utimbuf oldtimes_info;
	oldtimes_info.actime = ist_atime;
	oldtimes_info.modtime = ist_mtime;
	
	NSMutableDictionary *infoplist = [NSMutableDictionary dictionaryWithContentsOfFile:[application_basedir stringByAppendingString:@"Info.plist"]];
	if (infoplist == nil) {
		printf("error: Could not open Info.plist\n");
		goto fatalc;
	}
	
	if ([(NSString *)[ClutchConfiguration getValue:@"CheckMinOS"] isEqualToString:@"YES"]) {
		NSString *MinOS;
		if (nil != (MinOS = [infoplist objectForKey:@"MinimumOSVersion"])) {
			if (strncmp([MinOS UTF8String], "2", 1) == 0) {
				printf("notice: added SignerIdentity field (MinOS 2.X)\n");
				[infoplist setObject:@"Apple iPhone OS Application Signing" forKey:@"SignerIdentity"];
				[infoplist writeToFile:[application_basedir stringByAppendingString:@"Info.plist"] atomically:NO];
			}
		}
	}
	
	utime([[application_basedir stringByAppendingString:@"Info.plist"] UTF8String], &oldtimes_info);
	
	NSString *binary_name = [infoplist objectForKey:@"CFBundleExecutable"];
	
	NSString *fbinary_path = init_crack_binary(application_basedir, basename, workingDir, infoplist);
	if (fbinary_path == nil) {
		printf("error: Could not crack binary\n");
		goto fatalc;
	}
	
	NSMutableDictionary *metadataPlist = [NSMutableDictionary dictionaryWithContentsOfFile:[application_basedir stringByAppendingString:@"/../iTunesMetadata.plist"]];
	
	[[NSFileManager defaultManager] copyItemAtPath:[application_basedir stringByAppendingString:@"/../iTunesArtwork"] toPath:[workingDir stringByAppendingString:@"iTunesArtwork"] error:NULL];
    
	if (![[ClutchConfiguration getValue:@"RemoveMetadata"] isEqualToString:@"YES"]) {
        VERBOSE("Censoring iTunesMetadata.plist...");
		struct stat statbuf_metadata;
		stat([[application_basedir stringByAppendingString:@"/../iTunesMetadata.plist"] UTF8String], &statbuf_metadata);
		time_t mst_atime = statbuf_metadata.st_atime;
		time_t mst_mtime = statbuf_metadata.st_mtime;
		struct utimbuf oldtimes_metadata;
		oldtimes_metadata.actime = mst_atime;
		oldtimes_metadata.modtime = mst_mtime;
		
        NSString *fake_email;
        NSDate *fake_purchase_date;
        
        if (nil == (fake_email = [ClutchConfiguration getValue:@"MetadataEmail"])) {
            fake_email = @"steve@rim.jobs";
        }
        
        if (nil == (fake_purchase_date = [ClutchConfiguration getValue:@"MetadataPurchaseDate"])) {
            fake_purchase_date = [NSDate dateWithTimeIntervalSince1970:1251313938];
        }
        
		NSDictionary *censorList = [NSDictionary dictionaryWithObjectsAndKeys:fake_email, @"appleId", fake_purchase_date, @"purchaseDate", nil];
		if ([[ClutchConfiguration getValue:@"CheckMetadata"] isEqualToString:@"YES"]) {
			NSDictionary *noCensorList = [NSDictionary dictionaryWithObjectsAndKeys:
										  @"", @"artistId",
										  @"", @"artistName",
										  @"", @"buy-only",
										  @"", @"buyParams",
										  @"", @"copyright",
										  @"", @"drmVersionNumber",
										  @"", @"fileExtension",
										  @"", @"genre",
										  @"", @"genreId",
										  @"", @"itemId",
										  @"", @"itemName",
										  @"", @"gameCenterEnabled",
										  @"", @"gameCenterEverEnabled",
										  @"", @"kind",
										  @"", @"playlistArtistName",
										  @"", @"playlistName",
										  @"", @"price",
										  @"", @"priceDisplay",
										  @"", @"rating",
										  @"", @"releaseDate",
										  @"", @"s",
										  @"", @"softwareIcon57x57URL",
										  @"", @"softwareIconNeedsShine",
										  @"", @"softwareSupportedDeviceIds",
										  @"", @"softwareVersionBundleId",
										  @"", @"softwareVersionExternalIdentifier",
                                          @"", @"UIRequiredDeviceCapabilities",
										  @"", @"softwareVersionExternalIdentifiers",
										  @"", @"subgenres",
										  @"", @"vendorId",
										  @"", @"versionRestrictions",
										  @"", @"com.apple.iTunesStore.downloadInfo",
										  @"", @"bundleVersion",
										  @"", @"bundleShortVersionString", nil];
			for (id plistItem in metadataPlist) {
				if (([noCensorList objectForKey:plistItem] == nil) && ([censorList objectForKey:plistItem] == nil)) {
					printf("\033[0;37;41mwarning: iTunesMetadata.plist item named '\033[1;37;41m%s\033[0;37;41m' is unrecognized\033[0m\n", [plistItem UTF8String]);
				}
			}
		}
		
		for (id censorItem in censorList) {
			[metadataPlist setObject:[censorList objectForKey:censorItem] forKey:censorItem];
		}
		[metadataPlist removeObjectForKey:@"com.apple.iTunesStore.downloadInfo"];
		[metadataPlist writeToFile:[workingDir stringByAppendingString:@"iTunesMetadata.plist"] atomically:NO];
		utime([[workingDir stringByAppendingString:@"iTunesMetadata.plist"] UTF8String], &oldtimes_metadata);
		utime([[application_basedir stringByAppendingString:@"/../iTunesMetadata.plist"] UTF8String], &oldtimes_metadata);
	}
	
	NSString *crackerName = [ClutchConfiguration getValue:@"CrackerName"];
	if ([[ClutchConfiguration getValue:@"CreditFile"] isEqualToString:@"YES"]) {
        VERBOSE("Creating credit file...");
		FILE *fh = fopen([[workingDir stringByAppendingFormat:@"_%@", crackerName] UTF8String], "w");
		NSString *creditFileData = [NSString stringWithFormat:@"%@ (%@) Cracked by %@ using %s.", [infoplist objectForKey:@"CFBundleDisplayName"], [infoplist objectForKey:@"CFBundleVersion"], crackerName, CLUTCH_VERSION];
		fwrite([creditFileData UTF8String], [creditFileData lengthOfBytesUsingEncoding:NSUTF8StringEncoding], 1, fh);
		fclose(fh);
	}
    
    if (overdrive_enabled) {
        VERBOSE("Including overdrive dylib...");
        [[NSFileManager defaultManager] copyItemAtPath:@"/var/lib/clutch/overdrive.dylib" toPath:[workingDir stringByAppendingFormat:@"Payload/%@/overdrive.dylib", basename] error:NULL];
        
        VERBOSE("Creating fake SC_Info data...");
        // create fake SC_Info directory
        [[NSFileManager defaultManager] createDirectoryAtPath:[workingDir stringByAppendingFormat:@"Payload/%@/SF_Info/", basename] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        // create fake SC_Info SINF file
        FILE *sinfh = fopen([[workingDir stringByAppendingFormat:@"Payload/%@/SF_Info/%@.sinf", basename, binary_name] UTF8String], "w");
        void *sinf = generate_sinf([[metadataPlist objectForKey:@"itemId"] intValue], (char *)[crackerName UTF8String], [[metadataPlist objectForKey:@"vendorId"] intValue]);
        fwrite(sinf, CFSwapInt32(*(uint32_t *)sinf), 1, sinfh);
        fclose(sinfh);
        free(sinf);
        
        // create fake SC_Info SUPP file
        FILE *supph = fopen([[workingDir stringByAppendingFormat:@"Payload/%@/SF_Info/%@.supp", basename, binary_name] UTF8String], "w");
        uint32_t suppsize;
        void *supp = generate_supp(&suppsize);
        fwrite(supp, suppsize, 1, supph);
        fclose(supph);
        free(supp);
    }
    
    VERBOSE("Packaging IPA file...");
    
    // filename addendum
    NSString *addendum = @"";
    
    if (overdrive_enabled)
        addendum = @"-OD";

    
	NSString *ipapath;
	if ([[ClutchConfiguration getValue:@"FilenameCredit"] isEqualToString:@"YES"]) {
		ipapath = [NSString stringWithFormat:@"/var/root/Documents/Cracked/%@-v%@-%@%@.ipa", [[infoplist objectForKey:@"CFBundleDisplayName"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"], [infoplist objectForKey:@"CFBundleVersion"], crackerName, addendum];
	} else {
		ipapath = [NSString stringWithFormat:@"/var/root/Documents/Cracked/%@-v%@%@.ipa", [[infoplist objectForKey:@"CFBundleDisplayName"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"], [infoplist objectForKey:@"CFBundleVersion"], addendum];
	}
	[[NSFileManager defaultManager] createDirectoryAtPath:@"/var/root/Documents/Cracked/" withIntermediateDirectories:TRUE attributes:nil error:NULL];
	[[NSFileManager defaultManager] removeItemAtPath:ipapath error:NULL];
    
	//NSString *compressionArguments = [[ClutchConfiguration getValue:@"CompressionArguments"] stringByAppendingString:@" "];
    
    /*if (bash) {
        //BASH!!11!!
        
        NSDictionary *environment = [NSDictionary dictionaryWithObjectsAndKeys:
                                     @"ipapath", ipapath,
                                    // @"CompressionArguments", compressionArguments,
                                     @"appname", [infoplist objectForKey:@"CFBundleDisplayName"],
                                     @"appversion", [infoplist objectForKey:@"CFBundleVersion"],
                                     nil];
        
        NSTask * bash = [[NSTask alloc] init];
        [bash setLaunchPath:@"/bin/bash"];
        [bash setCurrentDirectoryPath:@"/"];
        NSPipe * out = [NSPipe pipe];
        [bash setStandardOutput:out];
        [bash setEnvironment:environment];
        
        [bash launch];
        [bash waitUntilExit];
        [bash release];
        
        NSFileHandle * read = [out fileHandleForReading];
        NSData * dataRead = [read readDataToEndOfFile];
        NSString * stringRead = [[[NSString alloc] initWithData:dataRead encoding:NSUTF8StringEncoding] autorelease];
        NSArray* dataArray = [stringRead componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        for (NSString *string in dataArray) {
            NSArray *split = [string componentsSeparatedByString:[NSCharacterSet whitespaceCharacterSet]];
            if ([[split objectAtIndex:0] isEqualToString:@"ipapath"]) {
                ipapath = [split objectAtIndex:1];
            }
            else if ([[split objectAtIndex:0] isEqualToString:@"CompressionArguments"]) {
                //compressionArguments = [split objectAtIndex:1];
            }
        }
        char* output = (char *)[[NSString stringWithFormat:@"Script output: %@", stringRead] UTF8String];
        VERBOSE(output);        
    }
    
	if (compressionArguments == nil)
		compressionArguments = @"";*/
    
    stop_bar();
    NOTIFY("Compressing original application (1/2)...");
    ZipArchive *archiver = [[ZipArchive alloc] init];
    [archiver CreateZipFile2:ipapath];
    zip_original(archiver, [application_basedir stringByAppendingString:@"../"], binary_name, ipapath);
    stop_bar();
    
    NOTIFY("Compressing cracked application (2/2)..");
    zip(archiver, workingDir);
    stop_bar();
    /*
    //add symlink
    
    [[NSFileManager defaultManager] moveItemAtPath:[workingDir stringByAppendingString:@"Payload"] toPath:[workingDir stringByAppendingString:@"Payload_1"] error:NULL];
    
     NOTIFY("Compressing second stage payload (2/2)...");
    
    [[NSFileManager defaultManager] createSymbolicLinkAtPath:[workingDir stringByAppendingString:@"Payload"] withDestinationPath:[application_basedir stringByAppendingString:@"/../"] error:NULL];
    zip(archiver, workingDir, compression_level);
    stop_bar();*/
    
    if (![archiver CloseZipFile2]) {
        printf("error: could not save zip file");
    }
    
    
//    
//	/*system([[NSString stringWithFormat:@"cd %@; zip %@-m -r \"%@\" * 2>&1> /dev/null", workingDir, compressionArguments, ipapath] UTF8String]);*/
//    
//	[[NSFileManager defaultManager] moveItemAtPath:[workingDir stringByAppendingString:@"Payload"] toPath:[workingDir stringByAppendingString:@"Payload_1"] error:NULL];
//    
//    NOTIFY("Compressing second stage payload (2/2)...");
//    
//	[[NSFileManager defaultManager] createSymbolicLinkAtPath:[workingDir stringByAppendingString:@"Payload"] withDestinationPath:[application_basedir stringByAppendingString:@"/../"] error:NULL];
//    
//	system([[NSString stringWithFormat:@"cd %@; zip %@-u -y -r -n .jpg:.JPG:.jpeg:.png:.PNG:.gif:.GIF:.Z:.gz:.zip:.zoo:.arc:.lzh:.rar:.arj:.mp3:.mp4:.m4a:.m4v:.ogg:.ogv:.avi:.flac:.aac \"%@\" Payload/* -x Payload/iTunesArtwork Payload/iTunesMetadata.plist \"Payload/Documents/*\" \"Payload/Library/*\" \"Payload/tmp/*\" \"Payload/*/%@\" \"Payload/*/SC_Info/*\" 2>&1> /dev/null", workingDir, compressionArguments, ipapath, binary_name] UTF8String]);
//	
    [archiver release];
    
    NSMutableDictionary *dict;
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/etc/clutch_cracked.plist"]) {
        dict = [[NSMutableDictionary alloc] initWithContentsOfFile:@"/etc/clutch_cracked.plist"];
    }
    else {
        [[NSFileManager defaultManager] createFileAtPath:@"/etc/clutch_cracked.plist" contents:nil attributes:nil];
        dict = [[NSMutableDictionary alloc] init];
    }
    [dict setObject:version forKey: [infoplist objectForKey:@"CFBundleDisplayName"]];
    [dict writeToFile:@"/etc/clutch_cracked.plist" atomically:YES];
	[[NSFileManager defaultManager] removeItemAtPath:workingDir error:NULL];
    [dict release];
	return ipapath;
	
fatalc: {
	[[NSFileManager defaultManager] removeItemAtPath:workingDir error:NULL];
	return nil;
}
}

NSString * init_crack_binary(NSString *application_basedir, NSString *bdir, NSString *workingDir, NSDictionary *infoplist) {
    VERBOSE("Performing cracking preflight...");
	NSString *binary_name = [infoplist objectForKey:@"CFBundleExecutable"];
	NSString *binary_path = [application_basedir stringByAppendingString:binary_name];
	NSString *fbinary_path = [workingDir stringByAppendingFormat:@"Payload/%@/%@", bdir, binary_name];
	
	NSString *err = nil;
	
	struct stat statbuf;
	stat([binary_path UTF8String], &statbuf);
	time_t bst_atime = statbuf.st_atime;
	time_t bst_mtime = statbuf.st_mtime;
	
	NSString *ret = crack_binary(binary_path, fbinary_path, &err);
	
	struct utimbuf oldtimes;
	oldtimes.actime = bst_atime;
	oldtimes.modtime = bst_mtime;
	
	utime([binary_path UTF8String], &oldtimes);
	utime([fbinary_path UTF8String], &oldtimes);
	
	if (ret == nil)
		printf("error: %s\n", [err UTF8String]);
	
	return ret;
}

NSString * crack_binary(NSString *binaryPath, NSString *finalPath, NSString **error) {
	[[NSFileManager defaultManager] copyItemAtPath:binaryPath toPath:finalPath error:NULL]; // move the original binary to that path
	NSString *baseName = [binaryPath lastPathComponent]; // get the basename (name of the binary)
	NSString *baseDirectory = [NSString stringWithFormat:@"%@/", [binaryPath stringByDeletingLastPathComponent]]; // get the base directory
	
	// open streams from both files
	FILE *oldbinary, *newbinary;
	oldbinary = fopen([binaryPath UTF8String], "r+");
	newbinary = fopen([finalPath UTF8String], "r+");
	
	// the first four bytes are the magic which defines whether the binary is fat or not
	uint32_t bin_magic;
	fread(&bin_magic, 4, 1, oldbinary);
	
	if (bin_magic == FAT_CIGAM) {
		// fat binary
		uint32_t bin_nfat_arch;
		fread(&bin_nfat_arch, 4, 1, oldbinary); // get the number of fat architectures in the file
		bin_nfat_arch = CFSwapInt32(bin_nfat_arch);
		
		// check if the architecture requirements of the fat binary are met
		// should be two architectures
		if (bin_nfat_arch != 2) {
			*error = @"Invalid architectures or headers.";
			goto c_err;
		}
		
		int local_arch = get_local_arch(); // get the local architecture
		
		// get the following fat architectures and determine which is which
		struct fat_arch armv6, armv7;
		fread(&armv6, sizeof(struct fat_arch), 1, oldbinary);
		fread(&armv7, sizeof(struct fat_arch), 1, oldbinary);
		if (only_armv7 == 1) {
            if (local_arch == ARMV6) {
                *error = @"You are not using an ARMV7 device";
                goto c_err;
            }
            VERBOSE("Only dumping ARMV7 portion because you said so");
            NOTIFY("Dumping ARMV7 portion...");
			// we can only crack the armv7 portion
			if (!dump_binary(oldbinary, newbinary, CFSwapInt32(armv7.offset), binaryPath)) {
                stop_bar();
				*error = @"Cannot crack ARMV7 portion.";
				goto c_err;
			}
            stop_bar();
			
            VERBOSE("Performing liposuction of ARMV7 mach object...");
			// lipo out the data
			NSString *lipoPath = [NSString stringWithFormat:@"%@_l", finalPath]; // assign a new lipo path
			FILE *lipoOut = fopen([lipoPath UTF8String], "w+"); // prepare the file stream
			fseek(newbinary, CFSwapInt32(armv7.offset), SEEK_SET); // go to the armv6 offset
			void *tmp_b = malloc(0x1000); // allocate a temporary buffer
			
			uint32_t remain = CFSwapInt32(armv7.size);
			
			while (remain > 0) {
				if (remain > 0x1000) {
					// move over 0x1000
					fread(tmp_b, 0x1000, 1, newbinary);
					fwrite(tmp_b, 0x1000, 1, lipoOut);
					remain -= 0x1000;
				} else {
					// move over remaining and break
					fread(tmp_b, remain, 1, newbinary);
					fwrite(tmp_b, remain, 1, lipoOut);
					break;
				}
			}
			
			free(tmp_b); // free temporary buffer
			fclose(lipoOut); // close lipo output stream
			fclose(newbinary); // close new binary stream
			fclose(oldbinary); // close old binary stream
			
			[[NSFileManager defaultManager] removeItemAtPath:finalPath error:NULL]; // remove old file
			[[NSFileManager defaultManager] moveItemAtPath:lipoPath toPath:finalPath error:NULL]; // move the lipo'd binary to the final path
			chown([finalPath UTF8String], 501, 501); // adjust permissions
			chmod([finalPath UTF8String], 0777); // adjust permissions
			
			return finalPath;

        }
		else if (local_arch != ARMV6) {
            VERBOSE("Application is a fat binary, cracking both architectures...");
            NOTIFY("Dumping ARMV7 portion...");
            
			// crack the armv7 portion
			if (!dump_binary(oldbinary, newbinary, CFSwapInt32(armv7.offset), binaryPath)) {
                stop_bar();
				*error = @"Cannot crack ARMV7 portion of fat binary.";
				goto c_err;
			}
			
			// we need to move the binary temporary as well as the decryption key names
			// this avoids the IV caching problem with fat binary cracking (and allows us to crack
			// the armv6 portion)
			VERBOSE("Preparing to crack ARMV6 portion...");
			// move the binary first
			
			NSString *orig_old_path = binaryPath; // save old binary path
			binaryPath = [binaryPath stringByAppendingString:@"_lwork"]; // new binary path
			[[NSFileManager defaultManager] moveItemAtPath:orig_old_path toPath:binaryPath error:NULL];
			fclose(oldbinary);
			oldbinary = fopen([binaryPath UTF8String], "r+");
			
			// move the SC_Info keys
			
			NSString *scinfo_prefix = [baseDirectory stringByAppendingFormat:@"SC_Info/%@", baseName];
			
			[[NSFileManager defaultManager] moveItemAtPath:[scinfo_prefix stringByAppendingString:@".sinf"] toPath:[scinfo_prefix stringByAppendingString:@"_lwork.sinf"] error:NULL];
			[[NSFileManager defaultManager] moveItemAtPath:[scinfo_prefix stringByAppendingString:@".supp"] toPath:[scinfo_prefix stringByAppendingString:@"_lwork.supp"] error:NULL];
			
			// swap the architectures
			
			uint8_t armv7_subtype = 0x09;
			uint8_t armv6_subtype = 0x06;
			
			fseek(oldbinary, 15, SEEK_SET);
			fwrite(&armv7_subtype, 1, 1, oldbinary);
			fseek(oldbinary, 35, SEEK_SET);
			fwrite(&armv6_subtype, 1, 1, oldbinary);
			
            PERCENT(-1);
            NOTIFY("Dumping ARMV6 portion...");
			// crack armv6 portion now
			BOOL res = dump_binary(oldbinary, newbinary, CFSwapInt32(armv6.offset), binaryPath);
			stop_bar();
            
			// swap the architectures back
			fseek(oldbinary, 15, SEEK_SET);
			fwrite(&armv6_subtype, 1, 1, oldbinary);
			fseek(oldbinary, 35, SEEK_SET);
			fwrite(&armv7_subtype, 1, 1, oldbinary);
			
			// move the binary and SC_Info keys back
			[[NSFileManager defaultManager] moveItemAtPath:binaryPath toPath:orig_old_path error:NULL];
			[[NSFileManager defaultManager] moveItemAtPath:[scinfo_prefix stringByAppendingString:@"_lwork.sinf"] toPath:[scinfo_prefix stringByAppendingString:@".sinf"] error:NULL];
			[[NSFileManager defaultManager] moveItemAtPath:[scinfo_prefix stringByAppendingString:@"_lwork.supp"] toPath:[scinfo_prefix stringByAppendingString:@".supp"] error:NULL];
			
			if (!res) {
				*error = @"Cannot crack ARMV6 portion of fat binary.";
				goto c_err;
			}
		} else {
            VERBOSE("Application is a fat binary, only cracking ARMV6 portion (we are on an ARMV6 device)...");
            NOTIFY("Dumping ARMV6 portion...");
			// we can only crack the armv6 portion
			if (!dump_binary(oldbinary, newbinary, CFSwapInt32(armv6.offset), binaryPath)) {
                stop_bar();
				*error = @"Cannot crack ARMV6 portion.";
				goto c_err;
			}
            stop_bar();
			
            VERBOSE("Performing liposuction of ARMV6 mach object...");
			// lipo out the data
			NSString *lipoPath = [NSString stringWithFormat:@"%@_l", finalPath]; // assign a new lipo path
			FILE *lipoOut = fopen([lipoPath UTF8String], "w+"); // prepare the file stream
			fseek(newbinary, CFSwapInt32(armv6.offset), SEEK_SET); // go to the armv6 offset
			void *tmp_b = malloc(0x1000); // allocate a temporary buffer
			
			uint32_t remain = CFSwapInt32(armv6.size);
			
			while (remain > 0) {
				if (remain > 0x1000) {
					// move over 0x1000
					fread(tmp_b, 0x1000, 1, newbinary);
					fwrite(tmp_b, 0x1000, 1, lipoOut);
					remain -= 0x1000;
				} else {
					// move over remaining and break
					fread(tmp_b, remain, 1, newbinary);
					fwrite(tmp_b, remain, 1, lipoOut);
					break;
				}
			}
			
			free(tmp_b); // free temporary buffer
			fclose(lipoOut); // close lipo output stream
			fclose(newbinary); // close new binary stream
			fclose(oldbinary); // close old binary stream
			
			[[NSFileManager defaultManager] removeItemAtPath:finalPath error:NULL]; // remove old file
			[[NSFileManager defaultManager] moveItemAtPath:lipoPath toPath:finalPath error:NULL]; // move the lipo'd binary to the final path
			chown([finalPath UTF8String], 501, 501); // adjust permissions
			chmod([finalPath UTF8String], 0777); // adjust permissions
			
			return finalPath;
		}
	} else {
        VERBOSE("Application is a thin binary, cracking single architecture...");
        NOTIFY("Dumping binary...");
		// thin binary, portion begins at top of binary (0)
		if (!dump_binary(oldbinary, newbinary, 0, binaryPath)) {
            stop_bar();
			*error = @"Cannot crack thin binary.";
			goto c_err;
		}
        stop_bar();
	}
	
	fclose(newbinary); // close the new binary stream
	fclose(oldbinary); // close the old binary stream

	return finalPath; // return cracked binary path
	
c_err:
	fclose(newbinary); // close the new binary stream
	fclose(oldbinary); // close the old binary stream
	[[NSFileManager defaultManager] removeItemAtPath:finalPath error:NULL]; // delete the new binary
	return nil;
}

NSString * genRandStringLength(int len) {
	NSMutableString *randomString = [NSMutableString stringWithCapacity: len];
	NSString *letters = @"abcdef0123456789";
	
	for (int i=0; i<len; i++) {
		[randomString appendFormat: @"%c", [letters characterAtIndex: arc4random()%[letters length]]];
	}
	
	return randomString;
}

int get_local_arch() {
	int i;
	int len = sizeof(i);
	
	sysctlbyname("hw.cpusubtype", &i, (size_t *) &len, NULL, 0);
	return i;
}
