/*
 * Quantification of protein expression in dark patches.
 * 
 * Macro used in paper "placeholder". In this case, dark patches are the mutant patches in channel1 and we delimite these pacthes to the domain
 * present in channel3. These patches are then used as ROIs to identify channel2 protein expression (using fluorescence intensity as proxy).
 * 
 * Author: José Serrado Marques, IGC, jpmarques@igc.gulbenkian.pt
 * 
 * v1.0 - 2020/06/26
 */
print("\\Clear");
// output folder for images, rois and results
input_dir = getDirectory("Choose input folder containing all images to be processed"); // top level directory
processed_images_dir = getDirectory("Output folder where to save processed images, rois and measurements");

// batch mode enables macro to run faster 
setBatchMode("hide");

// call function
processFolder(input_dir);

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
		if (current_file == "Composite.png") {
			processFile(input, processed_images_dir, current_file);
		}

	}
}


function processFile(input, processed_images_dir, file) { 
	// open file 
	path_file = input + File.separator + file;
	open(path_file);
	composite_image = getTitle();
	composite_name = substring(composite_image, 0, lengthOf(composite_image) - 4);
	run("Split Channels");
	run("Merge Channels...", "c1=["+ composite_image + " (green)] c2=["+ composite_image + " (blue)] c3=["+ composite_image + " (red)] create");
	Stack.setDisplayMode("grayscale");
	
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
	
	// filtering - median filter to better define edges (necessary to enhance limit of big region with channel3 signal) 
	selectWindow(c3_name);

	run("Median...", "radius=5");
	run("Gaussian Blur...", "sigma=5");
	
	// thresholding
	setAutoThreshold("Otsu dark");
	run("Convert to Mask"); // necessary command
	
	// Binary operations - Smooth Region with channel3 signal (Imaginal Disk)
	run("Options...", "iterations=1 count=1 black pad do=Nothing");
	run("Fill Holes");
	run("Dilate");
	run("Erode");
	run("Median...", "radius=8");
	
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
	roiManager("measure");
	
	rois_folder_name = composite_name + "_ROIS_and_measurements";
	output_rois_results = input + File.separator + rois_folder_name;
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
