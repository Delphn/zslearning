addpath anomalyFunctions/;
addpath toolbox/;
addpath toolbox/minFunc/;
addpath toolbox/pwmetric/;
addpath costFunctions/;

fields = {{'dataset',        'cifar10'};
          {'wordset',        'acl'};
          {'resolution',     11};
};

% Load existing model parameters, if they exist
for i = 1:length(fields)
    if exist('fullParams','var') && isfield(fullParams,fields{i}{1})
        disp(['Using the previously defined parameter ' fields{i}{1}])
    else
        fullParams.(fields{i}{1}) = fields{i}{2};
    end
end

dataset = fullParams.dataset;
wordset = fullParams.wordset;
trainFrac = 1;

if strcmp(dataset, 'cifar10')
    TOTAL_NUM_TRAIN = 50000;
    TOTAL_NUM_PER_CATEGORY = 5000;
    numCategories = 10;
    if isfield(fullParams,'zeroCategories')
        zeroCategories = fullParams.zeroCategories;
    else
        % 'cat', 'truck'
        zeroCategories = [ 4, 10 ];
    end
elseif strcmp(dataset, 'cifar96')
    TOTAL_NUM_TRAIN = 48000;
    TOTAL_NUM_PER_CATEGORY = 500;
    numCategories = 96;
    if isfield(fullParams,'zeroCategories')
        zeroCategories = fullParams.zeroCategories;
    else
        % 'boy', 'lion', 'orange', 'train', 'couch', 'house' 
        zeroCategories = [ 12, 42, 52, 87, 26, 36 ];
    end
else
    TOTAL_NUM_TRAIN = 53000;
    TOTAL_NUM_PER_CATEGORY = 500;
    numCategories = 106;
    if isfield(fullParams,'zeroCategories')
        zeroCategories = fullParams.zeroCategories;
    else
        % 'forest', 'lobster', 'boy', 'truck', 'orange', 'cat'
        zeroCategories = [ 33, 44, 12, 106, 52, 100 ];
    end
end
outputPath = sprintf('gauss_%s_%s', dataset, wordset);

if not(exist('skipLoad','var')) || skipLoad == false
    disp('Loading data');
    load(['image_data/features/' dataset '/train.mat']);
    load(['image_data/features/' dataset '/test.mat']);
    load(['word_data/' wordset '/' dataset '/wordTable.mat']);
end
    
if not(exist(outputPath, 'dir'))
    mkdir(outputPath);
end

disp('Zero categories:');
disp(zeroCategories);
nonZeroCategories = setdiff(1:numCategories, zeroCategories);

numTrain = (numCategories - length(zeroCategories)) / numCategories * TOTAL_NUM_TRAIN;
numTrainPerCat = 0.95 * numTrain / length(nonZeroCategories);
numValidatePerCat = numTrainPerCat * 0.05 / 0.95;
t = zeros(1, numTrain);
v = zeros(1, numValidate);
for i = 1:length(nonZeroCategories)
    [ ~, temp ] = find(trainY == nonZeroCategories(i));
    t((i-1)*numTrainPerCat+1:i*numTrainPerCat) = temp(1:numTrainPerCat);
    v((i-1)*numValidatePerCat+1:i*numValicatePerCat) = temp(numTrainPerCat+1:end);
end

% permute
order = randperm(numTrainPerCat * numCategories);
t = t(order);
order = randperm(numValidatePerCat * numCategories);
v = v(order);
X = trainX(:, t);
Y = trainY(t);
Xvalidate = trainX(:, v);
Yvalidate = trainY(v);
save(sprintf('%s/perm.mat', outputPath), 't', 'v');

disp('Training mapping function');
% Train mapping function
trainParams.imageDataset = fullParams.dataset;
[theta, trainParams ] = fastTrain(X, Y, trainParams, wordTable);
save(sprintf('%s/theta.mat', outputPath), 'theta', 'trainParams');

disp('Training seen softmax features');
mappedCategories = zeros(1, numCategories);
mappedCategories(nonZeroCategories) = 1:numCategories-length(zeroCategories);
trainParamsSeen.nonZeroShotCategories = nonZeroCategories;
[thetaSeen, trainParamsSeen] = nonZeroShotTrain(X, mappedCategories(Y), trainParamsSeen);
save(sprintf('%s/thetaSeenSoftmax.mat', outputPath), 'thetaSeen', 'trainParamsSeen');

disp('Training unseen softmax features');
trainParamsUnseen.zeroShotCategories = zeroCategories;
trainParamsUnseen.imageDataset = fullParams.dataset;
[thetaUnseen, trainParamsUnseen] = zeroShotTrain(trainParamsUnseen);
save(sprintf('%s/thetaUnseenSoftmax.mat', outputPath), 'thetaUnseen', 'trainParamsUnseen');

disp('Training Gaussian classifier using Mixture of Gaussians');
% Train Gaussian classifier
mapped = mapDoMap(X, theta, trainParams);
[mu, sigma, priors] = trainGaussianDiscriminant(mapped, Y, numCategories, wordTable);
sortedLogprobabilities = sort(predictGaussianDiscriminant(mapped, mu, sigma, priors, zeroCategories));

% Test
mappedTestImages = mapDoMap(testX, theta, trainParams);

resolution = fullParams.resolution;
gseenAccuracies = zeros(1, resolution);
gunseenAccuracies = zeros(1, resolution);
gaccuracies = zeros(1, resolution);
numPerIteration = numTrain / (resolution-1);
logprobabilities = predictGaussianDiscriminant(mappedTestImages, mu, sigma, priors, zeroCategories);
cutoffs = [ arrayfun(@(x) sortedLogprobabilities((x-1)*numPerIteration+1), 1:resolution-1) sortedLogprobabilities(end) ];
for i = 1:resolution
    cutoff = cutoffs(i);
    % Test Gaussian classifier
    fprintf('With cutoff %f:\n', cutoff);
    results = mapGaussianThresholdDoEvaluate( testX, testY, zeroCategories, label_names, wordTable, ...
        theta, trainParams, thetaSeen, trainParamsSeen, thetaUnseen, trainParamsUnseen, logprobabilities, cutoff, true);

    gseenAccuracies(i) = results.seenAccuracy;
    gunseenAccuracies(i) = results.unseenAccuracy;
    gaccuracies(i) = results.accuracy;
end
gseenAccuracies = fliplr(gseenAccuracies);
gunseenAccuracies = fliplr(gunseenAccuracies);
gAccuracies = fliplr(gAccuracies);

disp('Training Gaussian classifier using PDF');
% Train Gaussian classifier
mapped = mapDoMap(X, theta, trainParams);
[mu, sigma, priors] = trainGaussianDiscriminant(mapped, Y, numCategories, wordTable);
sortedLogprobabilities = sort(predictGaussianDiscriminantMin(mapped, mu, sigma, priors, zeroCategories));

% Test
mappedTestImages = mapDoMap(testX, theta, trainParams);

resolution = fullParams.resolution;
pdfSeenAccuracies = zeros(1, resolution);
pdfUnseenAccuracies = zeros(1, resolution);
pdfAccuracies = zeros(1, resolution);
numPerIteration = numTrain / (resolution-1);
logprobabilities = predictGaussianDiscriminantMin(mappedTestImages, mu, sigma, priors, zeroCategories);
cutoffs = [ arrayfun(@(x) sortedLogprobabilities((x-1)*numPerIteration+1), 1:resolution-1) sortedLogprobabilities(end) ];
for i = 1:resolution
    cutoff = cutoffs(i);
    % Test Gaussian classifier
    fprintf('With cutoff %f:\n', cutoff);
    results = mapGaussianThresholdDoEvaluate( testX, testY, zeroCategories, label_names, wordTable, ...
        theta, trainParams, thetaSeen, trainParamsSeen, thetaUnseen, trainParamsUnseen, logprobabilities, cutoff, true);

    pdfSeenAccuracies(i) = results.seenAccuracy;
    pdfUnseenAccuracies(i) = results.unseenAccuracy;
    pdfAccuracies(i) = results.accuracy;
end
pdfSeenAccuracies = fliplr(pdfSeenAccuracies);
pdfUnseenAccuracies = fliplr(pdfUnseenAccuracies);
pdfAccuracies = fliplr(pdfAccuracies);

disp('Training LoOP model');
resolution = fullParams.resolution - 1;
thresholds = 0:(1/resolution):1;
lambdas = 1:13;
knn = 20;
loopSeenAccuracies = zeros(length(lambdas), length(thresholds));
loopUnseenAccuracies = zeros(length(lambdas), length(thresholds));
loopAccuracies = zeros(length(lambdas), length(thresholds));
nonZeroCategoryIdPerm = randperm(length(nonZeroCategories));
bestLambdas = repmat(lambdas(length(lambdas)/2), 1, length(nonZeroCategories));
mappedValidationImages = mapDoMap(Xvalidate, theta, trainParams);

for k = 1:length(nonZeroCategories)
    changedCategory = nonZeroCategoryIdPerm(k);
    for i = 1:length(lambdas)
        tempLambdas = bestLambdas;
        tempLambdas(changedCategory) = lambdas(i);
        disp(tempLambdas);
        [ nplofAll, pdistAll ] = trainOutlierPriors(trainX, trainY, nonZeroCategories, numTrainPerCat, knn, tempLambdas);
        probs = calcOutlierPriors( mappedValidationImages, trainX, trainY, numTrainPerCat, nonZeroCategories, tempLambdas, knn, nplofAll, pdistAll );
        for t = 1:length(thresholds)
            fprintf('Threshold %f: ', thresholds(t));
            [~, results] = anomalyDoEvaluate(thetaSeen, ...
                trainParamsSeen, thetaUnseen, trainParamsUnseen, probs, Xvalidate, mappedValidationImages, Yvalidate, ...
                thresholds(t), zeroCategories, nonZeroCategories, false);
            loopSeenAccuracies(i, t) = results.seenAccuracy;
            loopUnseenAccuracies(i, t) = results.unseenAccuracy;
            loopAccuracies(i, t) = results.accuracy;
            fprintf('seen accuracy: %f, unseen accuracy: %f\n', results.seenAccuracy, results.unseenAccuracy);
        end
    end
    [~, t] = max(sum(loopAccuracies,2));
    bestLambdas(k) = t;
end
disp('Best:');
disp(bestLambdas);
% Do it again, with best lambdas
loopSeenAccuracies = zeros(1, length(thresholds));
loopUnseenAccuracies = zeros(1, length(thresholds));
loopAccuracies = zeros(1, length(thresholds));
[ nplofAll, pdistAll ] = trainOutlierPriors(trainX, trainY, nonZeroCategories, numTrainPerCat, knn, bestLambdas);
probs = calcOutlierPriors( mappedTestImages, trainX, trainY, numTrainPerCat, nonZeroCategories, bestLambdas, knn, nplofAll, pdistAll );
for t = 1:length(thresholds)
    fprintf('Threshold %f: ', thresholds(t));
            [~, results] = anomalyDoEvaluate(thetaSeen, ...
                trainParamsSeen, thetaUnseen, trainParamsUnseen, probs, testX, mappedTestImages, testY, ...
                thresholds(t), zeroCategories, nonZeroCategories, false);
    loopSeenAccuracies(t) = results.seenAccuracy;
    loopUnseenAccuracies(t) = results.unseenAccuracy;
    loopAccuracies(t) = results.accuracy;
    fprintf('accuracy: %f, seen accuracy: %f, unseen accuracy: %f\n', results.accuracy, results.seenAccuracy, results.unseenAccuracy);
end


zeroList = label_names(zeroCategories);
zeroStr = [sprintf('%s_',zeroList{1:end-1}),zeroList{end}];
save(sprintf('%s/out_%s.mat', outputPath, zeroStr), 'gSeenAccuracies', 'gUnseenAccuracies', 'gAccuracies', ...
    'loopSeenAccuracies', 'loopUnseenAccuracies', 'loopAccuracies', 'pdfSeenAccuracies', 'pdfUnseenAccuracies', ...
    'pdfAccuracies');
