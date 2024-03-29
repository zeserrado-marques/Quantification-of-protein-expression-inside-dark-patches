/*
 * Quantification of protein expression in dark patches.
 * 
 * Updated macro used in an unpublished paper. In this case, dark patches are the mutant patches in channel1 and we delimite these pacthes to the domain
 * present in channel3. These patches are then used as ROIs to identify channel2 protein expression (using fluorescence intensity as proxy).
 * 
 * Author: José Serrado Marques, IGC, jpmarques@igc.gulbenkian.pt
 * 
 * v1.2 - 2020/09/10
 * 
 * changes: 
 * - Use Gaussian Blur with radius of 20 and Threshold method Yen dark to better create the channel 3 domain's mask
 * - Binary operations on channel 3 mask removed, as the input images might have too much variation
 * - forced "run("Set Measurements...", "mean redirect=None decimal=3");" to make sure mean gray value is measured
 * - Added error detection if input image is or is not RGB with 3 channels or composite/grayscale with 3 channels
 */
print("\\Clear");
// choose parent input folder and output folder for images, rois and results
input_dir = getDirectory("Choose input folder containing all images to be processed"); // top level directory
processed_images_dir = getDirectory("Output folder where to save processed images, rois and measurements");

// batch mode enables macro to run faster 
setBatchMode("hide");
start_time = getTime();

// call function
processFolder(input_dir);

end_time = getTime();
runtime(start_time, end_time);

function processFolder(input) { 
	// get a list of file names (strings) and loop through them with for (condition is len(list_files))
	// if file is a directory, call back the same function with a new parameter, i.e, string of current dir + the name of 
	// dir found inside the current dir
	// this function scans. then calls another to do process when it found the correct file.
	list_files = getFileList(input);
	for (i = 0; i < lengthOf(list_files); i++) {
		current_file = list_files[i];
		print(current_file);
		if (File.isDirectory(input + File.separator + current_file)) {
			processFolder(input + File.separator + current_file);
		}
		if (endsWith(current_file, ".png") || endsWith(current_file, ".tif")) {
			processFile(input, processed_images_dir, current_file);
		}
	}
}


function processFile(input, processed_images_dir, file) { 
	// open file and split channels for mask creation
	path_file = input + File.separator + file;
	open(path_file);
	
	// get image info
	getDimensions(width, height, channels, slices, frames);
	image_info = getImageInfo();
	composite_image = getTitle();
	composite_name = substring(composite_image, 0, lengthOf(composite_image) - 4);
	run("Split Channels");
	list_open_images = getList("image.titles");


	// Checks if image is either RGB or has 3 channels
	if (indexOf(image_info, "RGB") != -1) {
		// check if RGB has an empty channel
		for (a = 0; a < nImages; a++) {
			selectWindow(list_open_images[a]);
			getStatistics(area, mean);
			if (mean == 0) {
				Dialog.create("Error");
				Dialog.addMessage("Please make sure the image is either a composite or RGB");
				Dialog.show();
				exit;
			}
		}	
		run("Merge Channels...", "c1=["+ composite_image + " (green)] c2=["+ composite_image + " (blue)] c3=["+ composite_image + " (red)] create");
		Stack.setDisplayMode("grayscale");
	} 
	else if (channels == 3){
		run("Merge Channels...", "c1=C1-" + composite_image + " c2=C2-" + composite_image + " c3=C3-" + composite_image + " create");
		print("hey, ho, let's go");
	}
	else {
		Dialog.create("Error");
		Dialog.addMessage("Please make sure the image is either a composite or RGB");
		Dialog.show();
		exit;
	}

	
	rename("Max_Zproject_image_3");
	to_measure_image = getTitle();
	run("Duplicate...", "title=original_image_3 duplicate");
	original_name = getTitle();
	run("Split Channels");
	selectWindow("C1-" + original_name);
	c1_name = getTitle();
	selectWindow("C2-" + original_name);
	c2_name = getTitle();
	selectWindow("C3-" + original_name);
	c3_name = getTitle();
	
	// filtering - guassian filter (necessary to enhance limit of big region with channel3 signal) 
	selectWindow(c3_name);
	run("Gaussian Blur...", "sigma=20");
		
	// thresholding
	// Yen threshold allows recovery of the region that was erased by guassian blur
	setAutoThreshold("Yen dark");
	run("Convert to Mask"); // necessary command
	
	// analyze particles to remove small objects, so have a single mask for Imaginal Disk
	run("Analyze Particles...", "size=10000-Infinity show=Masks exclude clear include");
	selectWindow("Mask of C3-original_image_3");
	mask_c3 = getTitle();
	
	// segmentation of c1 - dark patches
	selectWindow(c1_name);
	// image filtering
	run("Gaussian Blur...", "sigma=5");
	// In this case, we want the black patches so the "dark" option is not set in the setAutoThreshold function
	setAutoThreshold("Otsu");
	run("Convert to Mask");
	
	// Delimite dark patches inside the Imaginal Disk (channel 3 signal)
	imageCalculator("AND create", c1_name , mask_c3);
	selectWindow("Result of C1-original_image_3");
	patches_image = getTitle();
	// set  binary options and run Open binary function
	run("Options...", "iterations=3 count=1 black pad do=Open");
	//reset binary options
	run("Options...", "iterations=1 count=1 black pad do=Nothing");
	
	// final mask filtering - removing unwanted (i.e. small) patches
	run("Analyze Particles...", "size=500-Infinity circularity=0.15-1.00 show=Masks display exclude clear include add");
	
	run("Clear Results");
	
	// put ROIs on original image in 2nd channel to measure intensities
	selectWindow(to_measure_image);
	Stack.setChannel(2);
	// get roi manager count and rename ROIs
	roi_count = roiManager("count");
	roi_index_list = newArray(0);
	for (i = 0; i < roi_count; i++) {
		roi_index_list = Array.concat(roi_index_list, i);
		roiManager("select", i);
		patch_number = "patch_" + (i + 1);
		roiManager("rename", patch_number);
	}
	// measure all ROIs
	roiManager("select", roi_index_list);
	run("Set Measurements...", "mean redirect=None decimal=3"); // Added to force having mean as proxy value
	roiManager("measure");
	
	rois_folder_name = composite_name + "_ROIS_and_measurements";
	output_rois_results = processed_images_dir + File.separator + rois_folder_name; //replaced input by processed_images_dir 
	File.makeDirectory(output_rois_results);
	
	ROIs_name = composite_name + "_ROIs";
	results_name = composite_name + "_Results";
			
	roiManager("select", roi_index_list);
	roiManager("Save", output_rois_results + File.separator + ROIs_name + ".zip");
	
	selectWindow("Results");
	saveAs("Results", output_rois_results + File.separator + results_name + ".csv");
	
	selectWindow(to_measure_image);
	run("Select None");
	saveAs("Tiff", output_rois_results + File.separator + composite_name + ".tif");

	// close all windows, clear results and empty ROI Manager
	close("*");
	run("Clear Results");
	roiManager("select", roi_index_list);
	roiManager("delete");
}

function runtime(start_time, end_time) { 
	// print time in minutes and seconds
	total_time = end_time - start_time;
	minutes_remanider = total_time % (60 * 1000);
	minutes = (total_time - minutes_remanider) / (60 * 1000);
	seconds = minutes_remanider / 1000;
	print("Macro runtime was " + minutes + " minutes and " + seconds + " seconds.");
}

