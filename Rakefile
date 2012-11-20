# Rakefile to download a few datasets and configure their locations.
# INSTRUCTIONS:
# 1. Please run this after obtaining Kerberos tickets so that SSH access
#    can proceed without any password requirement. Alternatively, enter your
#    SSH password when prompted.

# Configuration information
CIFAR_FILE      = "cifar-10-matlab.tar.gz"
CIFAR_URL       = "http://www.cs.toronto.edu/~kriz/#{CIFAR_FILE}"
IMAGE_SSH_URL = "corn.stanford.edu:/mnt/glusterfs/mganjoo/image_data/"
TRAINX_FILENAME = "trainX.mat"
TRAINY_FILENAME = "trainY.mat"

# File and directory names
IMAGE_DATA_DIR  = "image_data"

desc "Directory for image data"
directory IMAGE_DATA_DIR

desc "Download the CIFAR-10 dataset"
task :download_cifar_dataset => IMAGE_DATA_DIR do
    Dir.chdir(IMAGE_DATA_DIR) do
        if !File.exist? CIFAR_FILE
            puts "Getting CIFAR dataset"
            `wget #{CIFAR_URL}`
        end
        `tar -xzf #{CIFAR_FILE}`
    end
end

desc "Download the training samples"
task :download_feature_set => IMAGE_DATA_DIR do
    Dir.chdir(IMAGE_DATA_DIR) do
        if !File.exist? TRAINX_FILENAME
            puts "Getting trainX data"
            `scp #{FEATURE_SSH_URL}#{TRAINX_FILENAME} .`
        end
        if !File.exist? TRAINY_FILENAME
            puts "Getting trainY data"
            `scp #{FEATURE_SSH_URL}#{TRAINY_FILENAME} .`
        end
    end
end

task :default => [ :download_cifar_dataset, :download_feature_set ]
