addpath toolbox/;
addpath toolbox/minFunc/;
addpath toolbox/pwmetric/;
addpath costFunctions/;

%% Model Parameters
fields = {{'wordDataset',         'acl'};            % type of embedding dataset to use ('turian.200', 'acl')
          {'imageDataset',        'cifar10'};        % CIFAR dataset type
          {'lambda',              1E-3};   % regularization parameter
          {'numReplicate',        0};     % one-shot replication
          {'dropoutFraction',     1};    % drop-out fraction
          {'costFunction',        @softmaxCost}; % training cost function
          {'trainFunction',       @trainLBFGS}; % training function to use
          {'hiddenSize',          100};
          {'maxIter',             200};    % maximum number of minFunc iterations on a batch
          {'maxPass',             1};      % maximum number of passes through training data
          {'disableAutoencoder',  true};   % whether to disable autoencoder
          {'maxAutoencIter',      50};     % maximum number of minFunc iterations on a batch
          
          % options
          {'batchFilePrefix',     'default_batch'};  % use this to choose different batch sets (common values: default_batch or mini_batch)
          {'zeroFilePrefix',      'zeroshot_batch'}; % batch for zero shot images
          {'fixRandom',           false};  % whether to fix the random number generator
          {'enableGradientCheck', true};  % whether to enable gradient check
          {'preTrain',            true};   % whether to train on non-zero-shot first
          {'reloadData',          true};   % whether to reload data when this script is called (disable for batch jobs)
          
          % Old parameters, just keep for compatibility
          {'saveEvery',           5};      % number of passes after which we need to do intermediate saves
          {'oneShotMult',         1.0};    % multiplier for one-shot multiplier
          {'autoencMultStart',    0.01};   % starting value for autoenc mult
          {'sparsityParam',       0.035};  % desired average activation of the hidden units.
          {'beta',                5};      % weight of sparsity penalty term
};

% Load existing model parameters, if they exist
for i = 1:length(fields)
    if exist('trainParams','var') && isfield(trainParams,fields{i}{1})
        disp(['Using the previously defined parameter ' fields{i}{1}])
    else
        trainParams.(fields{i}{1}) = fields{i}{2};
    end
end

if not(isfield(trainParams, 'outputPath'))
    outputPath = sprintf('map-%s-%s-%s-iter_%d-pass_%d-noae_%d-aeiter_%d-reg_%.0e-1s_%d-dfrac_%.2f-%s', ...
        func2str(trainParams.costFunction), trainParams.imageDataset, trainParams.wordDataset, trainParams.maxIter, ...
        trainParams.maxPass, trainParams.disableAutoencoder, trainParams.maxAutoencIter, trainParams.lambda, trainParams.numReplicate, ...
        trainParams.dropoutFraction, datestr(now, 30));
else
    outputPath = trainParams.outputPath;
end

fprintf('<BEGIN_EXPERIMENT %s>\n', outputPath);
disp('Parameters:');
disp(trainParams);

% Fix the random number generator if needed
if trainParams.fixRandom == true
    RandStream.setGlobalStream(RandStream('mcg16807','Seed', 0));
end

trainParams.f = @tanh;             % function to use in the neural network activations
trainParams.f_prime = @tanh_prime; % derivative of f
trainParams.doEvaluate = true;
trainParams.testFilePrefix = 'zeroshot_test_batch';
trainParams.autoencMult = trainParams.autoencMultStart;

%% Load batches of training images
batchFilePath   = ['image_data/batches/' trainParams.imageDataset];
files = dir([batchFilePath '/' trainParams.batchFilePrefix '*.mat']);
numBatches = length(files) - 1;
assert(numBatches >= 1);
clear files;

disp('Loading batches of training images and initializing parameters');
batches = cell(1, numBatches);
for i = 1:numBatches
    [batches{i}.imgs, batches{i}.categories, categoryNames] = loadBatch(trainParams.batchFilePrefix, trainParams.imageDataset, i);
end
trainParams.imageColumnSize = size(batches{1}.imgs, 1);

%% Load one-shot training images
[zeroimgs, zerocategories, zeroCategoryNames] = loadBatch(trainParams.zeroFilePrefix, trainParams.imageDataset, 1);
dataToUse.zeroimgs = zeroimgs(:, 1);
dataToUse.zerocategories = zerocategories(:, 1);

%% Load word representations
disp('Loading word representations');
t = load(['word_data/' trainParams.wordDataset '/' trainParams.imageDataset '/wordTable.mat']);
wordTable = zeros(size(t.wordTable, 1), length(categoryNames) + length(zeroCategoryNames));
for i = 1:length(categoryNames)
    j = ismember(t.label_names, categoryNames{i}) == true;
    wordTable(:, i) = t.wordTable(:, j);
end
origNumCategories = length(categoryNames);
for i = 1:length(zeroCategoryNames)
    j = ismember(t.label_names, zeroCategoryNames{i}) == true;
    wordTable(:, i + length(categoryNames)) = t.wordTable(:, j);
    zerocategories = zerocategories + length(categoryNames);
end

% load unseen word table
if strcmp(dataset, 'cifar10') == true
    zeroCategories = [ 4, 10 ];
    unseenWordTable = t.wordTable(:, zeroCategories);
end
clear t;

%% Load validation batch
disp('Loading validation batch');
[dataToUse.validImgs, dataToUse.validCategories, ~] = loadBatch(trainParams.batchFilePrefix, trainParams.imageDataset, numBatches+1);

%% Load test images
disp('Loading test images');
[dataToUse.testImgs, dataToUse.testCategories, dataToUse.testOriginalCategoryNames] = loadBatch(trainParams.testFilePrefix, trainParams.imageDataset);

% Change the names of the categories to be included in the test set
dataset = trainParams.imageDataset;
if strcmp(dataset, 'cifar10') == true
    testCategoryNames = loadCategoryNames(dataset);
elseif strcmp(dataset, 'cifar96') == true
    testCategoryNames = loadCategoryNames(dataset, { 'orange', 'camel' });
elseif strcmp(dataset, 'cifar106') == true
    testCategoryNames = loadCategoryNames(dataset, { 'truck', 'lion', 'orange', 'camel' });
else
    error('Not a valid dataset');
end
w = load(['word_data/' trainParams.wordDataset '/' dataset '/wordTable.mat']);
trainParams.embeddingSize = size(w.wordTable, 1);
dataToUse.testWordTable = zeros(trainParams.embeddingSize, length(testCategoryNames));
for categoryIndex = 1:length(testCategoryNames)
    icategoryWord = ismember(w.label_names, testCategoryNames(categoryIndex)) == true;
    dataToUse.testWordTable(:, categoryIndex) = w.wordTable(:, icategoryWord);
end
dataToUse.testCategoryNames = testCategoryNames;

% Load 50 random words from the vocabulary for an alternative
% evaluation method
disp('Loading random words for evaluation');
ee = load(['word_data/' trainParams.wordDataset '/embeddings.mat']);
vv = load(['word_data/' trainParams.wordDataset '/vocab.mat']);
% Pick 50 random nouns including the test category
randIndices = randi(length(vv.vocab), 1, 49);
if strcmp(dataset, 'cifar10') == true
    extraNames = { 'cat', 'truck' };
elseif strcmp(dataset, 'cifar96') == true
    extraNames = { 'lion', 'boy' };
elseif strcmp(dataset, 'cifar106') == true
    extraNames = { 'cat', 'boy' };
else
    error('Not a valid dataset');
end
dataToUse.randCategoryNames = [ extraNames vv.vocab(:, randIndices) ];
dataToUse.randWordTable = [ zeros(trainParams.embeddingSize, length(extraNames)) ee.embeddings(:, randIndices) ];
for categoryIndex = 1:length(extraNames)
    icategoryWord = ismember(vv.vocab, testCategoryNames(categoryIndex)) == true;
    dataToUse.randWordTable(:, categoryIndex) = ee.embeddings(:, icategoryWord);
end
clear ee vv;

%% First check the gradient of our minimizer
if trainParams.enableGradientCheck
    dimgs = rand(4, 10);
    dcategories = randi(5, 1, 10);
    dwordTable = wordTable(1:4, 1:6);
    ddataToUse = prepareData( dimgs, dcategories, dwordTable );
    ddataToUse.zeroimgs = rand(4, 4);
    ddataToUse.zerocategories = ones(1, 4) + 5;
    debugOptions.Method = 'lbfgs';
    debugOptions.display = 'off';
    debugOptions.DerivativeCheck = 'on';
    debugOptions.maxIter = 1;
    debugParams = trainParams;
    debugParams.autoencMult = 1E-2;
    debugParams.numReplicate = 3;
    debugParams.doEvaluate = false;
    if strcmp(func2str(debugParams.costFunction), 'softmaxCost')
        debugParams.outputSize = size(ddataToUse.wordTable, 2);
    else
        debugParams.outputSize = size(ddataToUse.wordTable, 1);
    end
    debugParams.inputSize = size(ddataToUse.imgs, 1);
    debugParams.embeddingSize = size(dwordTable, 1);
    debugParams.imageColumnSize = size(dimgs, 1);
    [ debugTheta, debugParams.decodeInfo ] = initializeParameters(debugParams);
    [~, ~, ~, ~] = minFunc( @(p) debugParams.costFunction(p, ddataToUse, debugParams), debugTheta, debugOptions);
end 

% Initialize actual weights
disp('Initializing parameters');
trainParams.inputSize = size(batches{1}.imgs, 1);
if strcmp(func2str(debugParams.costFunction), 'softmaxCost')
    trainParams.outputSize = origNumCategories;
else
    trainParams.outputSize = size(wordTable, 1);
end
[ theta, trainParams.decodeInfo ] = initializeParameters(trainParams);
dataToUse.categoryNames = categoryNames;

if not(exist(outputPath, 'dir'))
    mkdir(outputPath);
end

globalStart = tic;
for j = 1:trainParams.maxPass
    for i = 1:numBatches
        dataToUse.imgs = batches{i}.imgs;
        dataToUse.categories = batches{i}.categories;
        dataToUse.wordTable = wordTable;
        theta = trainParams.trainFunction(trainParams, dataToUse, theta);
    end
end

gtime = toc(globalStart);
fprintf('Total time: %f s\n', gtime);

%% Save learned parameters
disp('Saving final learned parameters');
save(sprintf('%s/params_final.mat', outputPath), 'theta', 'trainParams');
disp('<END_EXPERIMENT>');

