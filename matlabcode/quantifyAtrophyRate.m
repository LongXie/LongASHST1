function quantifyAtrophyRate(MEACSV, OUTCSV)

%%
%MEACSV = '/data/jet/longxie/ASHS_T1/longitudinal_pipeline_package/test/output/011_S_0021/work/quantification/measurements.csv';

% load data
longdata = dataset('file', MEACSV, 'Delimiter', ',');

% some basic info
SIDES = {'L', 'R'};
nside = length(SIDES);
SUBS = {'AHippo','PHippo','Hippo','ERC', 'BA35', 'BA36', 'PHC'};
nsubs = length(SUBS);

% init
outrow = dataset();
outrow.ID = longdata.ID{1};

% look for qualify cases
cases = longdata(longdata.ALOHA_success == 1, :);

if isempty(cases)

    outrow.NTP = 1;
    outrow.MeanDateDiff = nan;
    outrow.MaxDateDiff = nan;

    for j = 1:nside
    side = SIDES{j};
    for k = 1:nsubs
    sub = SUBS{k};
    eval(sprintf('outrow.%s_%s_VOL_ChangeAnnualizedAllTP = nan;', side, sub));
    eval(sprintf('outrow.%s_%s_VOL_ChangeAnnualizedPercentageAllTP = nan;', side, sub));
    end
    end
    
    for k = 1:nsubs
    sub = SUBS{k};
    eval(sprintf('outrow.M_%s_VOL_ChangeAnnualizedAllTP = nan;', sub));
    eval(sprintf('outrow.M_%s_VOL_ChangeAnnualizedPercentageAllTP = nan;', sub));
    end
    
else
    
    % baseline info
    ntp = size(cases, 1);
    %outrow = cases(1,:);
    outrow.NTP = ntp+1;
    date_diff = double(cases.datediff)/365;
    outrow.MeanDateDiff = mean(date_diff);
    outrow.MaxDateDiff = max(date_diff);
    
    for j = 1:nside
    side = SIDES{j};
    for k = 1:nsubs
    sub = SUBS{k};

    % get baseline and followup measurements
    eval(sprintf('bl = double(cases.%s_%s_VOL_BL);', side, sub));
    eval(sprintf('fu = double(cases.%s_%s_VOL_FU);', side, sub));
    atrophy = (bl - fu) ./ bl;

    % Construct the first part of the least squares problem
    w = 1;%date_diff/mean(date_diff);
    X1 = full(sparse(1:ntp,1,w.*(1-atrophy),ntp,ntp+3) + ...
        sparse(1:ntp,2:ntp+1,-w, ntp, ntp+3));
    %X1 = full(sparse(1:ntp,1,date_diff.*(1-atrophy),ntp,ntp+3) + ...
    %    sparse(1:ntp,2:ntp+1,-date_diff, ntp, ntp+3));
    Y1 = zeros(ntp,1);

    % get the second part of the equations
    X2 = full(sparse(1,1,1,1,ntp+3));
    Y2 = bl(1);

    % get the third part of the equations
    X3 = full(sparse(1:ntp+1,1:ntp+1,-1,ntp+1,ntp+3) + ...
        sparse(1:ntp+1,ntp+2,1,ntp+1,ntp+3) + ...
        sparse(2:ntp+1,ntp+3,date_diff,ntp+1,ntp+3));
    Y3 = zeros(ntp+1,1);

    % Combine into a single design matrix
    X = [X1; X2; X3];
    Y = [Y1; Y2; Y3];

    % Add a column to account for bias (hopefully very small)
    %Xb = [ [ones(ntp,1); zeros(ntp+1,1)], X];
    Xb = X;       

    % Solve the least squares system
    vopt = (Xb' * Xb) \ (Xb' * Y);

    % output
    ARate = vopt(end);
    ARatePerc = ARate / bl(1) *100;
    eval(sprintf('outrow.%s_%s_VOL_ChangeAnnualizedAllTP = %4.4f;', side, sub, ARate));
    eval(sprintf('outrow.%s_%s_VOL_ChangeAnnualizedPercentageAllTP = %4.4f;', side, sub, ARatePerc));

    end
    end
    
    % compute bilateral mean
    for k = 1:nsubs
    sub = SUBS{k};

    eval(sprintf('outrow.M_%s_VOL_ChangeAnnualizedAllTP = (outrow.L_%s_VOL_ChangeAnnualizedAllTP + outrow.R_%s_VOL_ChangeAnnualizedAllTP)/2;', sub, sub, sub));
    eval(sprintf('outrow.M_%s_VOL_ChangeAnnualizedPercentageAllTP = (outrow.L_%s_VOL_ChangeAnnualizedPercentageAllTP + outrow.R_%s_VOL_ChangeAnnualizedPercentageAllTP)/2;', sub, sub, sub));

    end
    
end

% save the result
export(outrow, 'File', OUTCSV, 'Delimiter', ',');

