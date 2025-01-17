classdef PR_Forage < handle
  % Matlab class for running an experimental protocl
  %
  % The class constructor can be called with a range of arguments:
  %
 
  properties (Access = public) 
       Iti double = 1;             % default Iti duration
       startTime double = 0;       % trial start time
       itiStart double = 0;        % start of iti interval
       rewardCount double = 0;     % counter for reward drops
       rewardGap double = 0;       % gap for next target onset
       rewardTime double = 0;      % store time of last reward
  end
      
  properties (Access = private)
    winPtr; % ptb window
    state double = 0;      % state counter
    error double = 0;      % error state in trial
    %*********
    S;              % copy of Settings struct (loaded per trial start)
    P;              % copy of Params struct (loaded per trial)
    trialsList;        % store copy of trial list (not good to keep in S struct)
    %********* stimulus structs for use
    Faces;             % object that stores face images for use
    faceTime = 0.1;    % time for showing face stimulus
    hProbe = [];       % object for foraging stimuli
    probeNum = 1;      % number of foraging stimuli
    oriNum = 1;        % number of oriented textures to draw from for probe
    targOri = 1;       % current orientation of target probe
    noiseStim = 0;     % which noise stim (if long term duration)
    hNoise = [];       % random flashing background grating
    noiseNum = 1;      % number of oriented textures
    spatoris = [];     % list of tested orientations
    spatfreqs = [];    % list of tested spatial freqs
    %******* parameters for Noise History grating stimulus 
    noisetype = 0;     % type of background noise stimulus
    NoiseHistory = []; % list of noise frames over trial and their times
    FrameCount = 0;    % count noise frames
    ProbeHistory = []; % list of history for probe objects
    PFrameCount = 0;   % count probe frames (should be same as noise for now)
    MaxFrame = (120*20); % twenty second maximum
    TrialDur = 0;      % store internally the trial duration (make less than 20)
    %******** parameters for positioning foraging stimuli
    PosList = [];      % will be x,y positions of stimuli
    MovList = [];      % speed vector if a moving item
    FixTime = 0;      % will be duration item is fixated
    MovStep = 0;       % vector amplitude motion step if moving probe
    %*******
    FixCount = 0;      % count fixation of probe events
    FixHit = [];       % list of positions where probe hits occured
    FixMax = 20;        % maximum fixations in any trial
    %**********************************
    D = struct;        % store PR data for end plot stats, will store dotmotion array
  end
  
  methods (Access = public)
    function o = PR_Forage(winPtr)
      o.winPtr = winPtr;
      o.trialsList = [];  % should be set by generate call
    end
    
    function state = get_state(o)
        state = o.state;
    end
    
    function initFunc(o,S,P);
  
       %********** Set-up for trial indexing (required) 
       cors = [0,4];  % count these errors as correct trials
       reps = [1,2];  % count these errors like aborts, repeat
       o.trialsList = [];  % empty for this protocol
       %**********
      
       %******* init Noise History with MaxDuration **************
       o.ProbeHistory = zeros(o.MaxFrame,4);  % x,y,ori,fixated
       
       %******* init reward face for correct trials
       o.faceTime = P.faceTime;
       o.Faces = stimuli.gaussimages(o.winPtr,'bkgd',S.bgColour,'gray',false);   % color images
       o.Faces.loadimages('./SupportData/MarmosetFaceLibrary.mat');
       o.Faces.position = [0,0]*S.pixPerDeg + S.centerPix;
       o.Faces.radius = round(P.faceradius*S.pixPerDeg);
       o.Faces.imagenum = 1;  % start first face
       o.Faces.transparency = -1;  % blend into background

       %***** create a Gabor target grating
       o.FixTime = 0;
       o.oriNum = P.orinum;
       o.hProbe = cell(1,o.oriNum);
       o.targOri = 1;
       for kk = 1:o.oriNum
           %*******
           o.hProbe{kk} = stimuli.grating(o.winPtr);  % grating probe
           o.hProbe{kk}.transparent = -P.probecon;  % blend in proportion to gauss
           o.hProbe{kk}.gauss = true;
           o.hProbe{kk}.pixperdeg = S.pixPerDeg;
           o.hProbe{kk}.radius = round(P.proberadius*S.pixPerDeg);
          
           o.hProbe{kk}.range = P.proberange;
           o.hProbe{kk}.square = false;
           o.hProbe{kk}.bkgd = P.bkgd;
           %**************
           o.hProbe{kk}.position = [S.centerPix(1),S.centerPix(2)];
           o.hProbe{kk}.phase = P.phase;
           o.hProbe{kk}.cpd = P.cpd;
           if (kk < o.oriNum)
              o.hProbe{kk}.orientation = (kk-1)*180/(o.oriNum-1);
              o.hProbe{kk}.orientation = o.hProbe{kk}.orientation + P.prefori;
           else
              o.hProbe{kk}.orientation = 0; 
              o.hProbe{kk}.cpd = 0;
              o.hProbe{kk}.phase = 0;
           end
           %**************
           o.hProbe{kk}.updateTextures();
           %****************
       end
       %***** but don't set stim properties yet ... done per trial
       
       %******* SETUP NOISE BACKGROUND BASED ON TYPE, HARTLEY, SPATIAL, ETC
       o.noisetype = P.noisetype;
       %**********
       % for o.noisetype == 0 would be no background at all!
       if (o.noisetype == 0) % no background
          o.noiseNum = 0;
          o.hNoise = [];
       end
       %**********
       if (o.noisetype == 1) % use Hartley background
           %*************
           o.NoiseHistory = zeros(o.MaxFrame,2);
           % Make Noise stimulus textures, pre-allocate textures for speed
           if (P.spfnum > 1) && (P.spfmax > P.spfmin)
              o.spatfreqs = exp( log(P.spfmin):(log(P.spfmax)-log(P.spfmin))/(P.spfnum-1):log(P.spfmax));
           else
              o.spatfreqs = ones(1,P.spfnum) * P.spfmax;
           end
           %************
           o.spatoris = (0:(P.noiseorinum-1))*180/P.noiseorinum; 
           o.noiseNum = P.noiseorinum * P.spfnum;
           o.hNoise = cell(1,o.noiseNum);
           for k = 1:o.noiseNum
               o.hNoise{k} = stimuli.grating(o.winPtr);  % grating probe
               o.hNoise{k}.position = S.centerPix; 
               if isinf(P.noiseradius)
                   o.hNoise{k}.radius = Inf;    %fill entire screen
                   o.hNoise{k}.screenRect = S.screenRect;
               else
                   o.hNoise{k}.radius = round(P.noiseradius*S.pixPerDeg);
               end
               %*********
               kori = 1 + mod((k-1),P.noiseorinum);
               kspf = 1 + floor( (k-1)/P.noiseorinum);
               %*******
               o.hNoise{k}.orientation = o.spatoris(kori);
               o.hNoise{k}.phase = 0;
               o.hNoise{k}.cpd = o.spatfreqs(kspf);   
               o.hNoise{k}.range = P.noiserange;
               o.hNoise{k}.square = logical(P.squareWave);
               o.hNoise{k}.gauss = true;
               o.hNoise{k}.bkgd = P.bkgd;
               o.hNoise{k}.transparent = 0.5;
               o.hNoise{k}.pixperdeg = S.pixPerDeg;
               o.hNoise{k}.updateTextures();
           end 
           %****************
       end
       %******** Spatial noise background
       if (o.noisetype == 2) % use Spatial background
           o.noiseNum = P.snoisenum * 2;
           o.NoiseHistory = zeros(o.MaxFrame,(1+(o.noiseNum * 2)));  % store time, then x,y positions
           o.hNoise = cell(1,o.noiseNum);
           if (0) % comment for now, using ovals instead
             for k = 1:o.noiseNum
               o.hNoise{k} = stimuli.grating(o.winPtr);  % grating probe
               o.hNoise{k}.radius = round((P.snoisediam/2)*S.pixPerDeg);
               o.hNoise{k}.orientation = 0; % cpd will be zero => all one color
               if (mod(k,2) == 1)
                   o.hNoise{k}.phase = 0;   % white
               else
                   o.hNoise{k}.phase = 180; % black
               end
               o.hNoise{k}.cpd = 0; % when cpd is zero, you get a Gauss
               o.hNoise{k}.range = P.range;
               o.hNoise{k}.square = false; % true;  % if you want circle
               o.hNoise{k}.gauss = true;
               o.hNoise{k}.bkgd = P.bkgd;
               o.hNoise{k}.transparent = -0.5;
               o.hNoise{k}.pixperdeg = S.pixPerDeg;
               o.hNoise{k}.updateTextures();
             end
           end
       end
       %********* CSD will be similar to hartley, but all white (SF=0)
       %******* and a different on duration of stimulus 
       %**********
       if (o.noisetype == 3) % use Hartley background
           %*************
           o.NoiseHistory = zeros(o.MaxFrame,2);
           o.noiseNum = 1;
           o.hNoise = cell(1,o.noiseNum);
           for k = 1:o.noiseNum
               o.hNoise{k} = stimuli.grating(o.winPtr);  % grating probe
               o.hNoise{k}.position = S.centerPix; 
               o.hNoise{k}.radius = Inf;    %fill entire screen
               o.hNoise{k}.screenRect = S.screenRect;
               %*********
               o.hNoise{k}.orientation = 0;
               o.hNoise{k}.phase = 0;  % white stim
               o.hNoise{k}.cpd = 0;  % all field   
               o.hNoise{k}.range = P.noiserange;
               o.hNoise{k}.square = logical(P.squareWave);
               o.hNoise{k}.gauss = true;
               o.hNoise{k}.bkgd = P.bkgd;
               o.hNoise{k}.transparent = 0.5;
               o.hNoise{k}.pixperdeg = S.pixPerDeg;
               o.hNoise{k}.updateTextures();
           end 
           %****************
       end
       %**********************************************************
       
       %********* CSD will be similar to hartley, but all white (SF=0)
       %******* and a different on duration of stimulus 
       %**********
       if (o.noisetype == 4) % use Hartley background
           %*************
           o.NoiseHistory = zeros(o.MaxFrame,2);
           o.noiseNum = P.noisenum * P.numSpeed;
           o.hNoise = cell(1,o.noiseNum);
           if (P.numSpeed > 1)
               sn = P.numSpeed;
               smax = P.dotSpeedMax;
               smin = P.dotSpeedMin;
               speeds = exp( log(smin):((log(smax)-log(smin))/(sn-1)):log(smax) );
           else
               speeds = P.dotSpeed;
           end
           for k = 1:o.noiseNum
               ori_k = mod((k-1),P.noisenum);
               spd_k = 1 + floor((k-1)/P.noisenum);
               %*******
               o.hNoise{k} = stimuli.dots(o.winPtr);
               o.hNoise{k}.mode=1; % dot distribution
               o.hNoise{k}.dist=0; % dot distrib
               o.hNoise{k}.numDots = P.dotNum; % number of dots in dot field 
               o.hNoise{k}.position = S.centerPix; % where to plot dot field 
               ango = (ori_k-1) * 360 / P.noisenum;
               o.hNoise{k}.direction = ango;  % into degrees/ direction of motion 
               o.hNoise{k}.bandwdth = 1; 
               o.hNoise{k}.lifetime = P.dotLifeTime; %how long the dots last
               %************
               o.hNoise{k}.maxRadius = inf;  % same pixel size as aperture (radius of the dot field)
               o.hNoise{k}.Xtop = (P.noisewidth * S.pixPerDeg);
               o.hNoise{k}.Xbot = -(P.noisewidth * S.pixPerDeg);
               o.hNoise{k}.Ytop = (P.noiseheight * S.pixPerDeg);
               o.hNoise{k}.Ybot = -(P.noiseheight * S.pixPerDeg);
               %************
               o.hNoise{k}.speed = (speeds(spd_k)*S.pixPerDeg)/S.frameRate;   %(speed of dots)
               o.hNoise{k}.beforeTrial;
               o.hNoise{k}.colour =(P.bkgd-P.range) * ones(1,3);
               o.hNoise{k}.size = round(P.dotSize*S.pixPerDeg);   % size of the dots
               o.hNoise{k}.theta=0;
               o.hNoise{k}.gaussian = false;
           end 
           %****************
       end
       %******** Spatial noise background
       if (o.noisetype == 5) % use Spatial background
           o.noiseNum = P.snoisenum;
           o.NoiseHistory = zeros(o.MaxFrame,(1+(o.noiseNum * 4)));  % store time, then x,y,dir,life positions
           o.hNoise = zeros(5,o.noiseNum);
           %****** initialize dots and lifetimes
           for kk = 1:o.noiseNum
               %*******
               sx = (rand - 0.5) * 2 * P.snoisewidth;
               sy = (rand - 0.5) * 2 * P.snoiseheight;
               o.hNoise(1,kk) = sx;
               o.hNoise(2,kk) = sy;
               dir = randi(P.snoisedirs);
               o.hNoise(5,kk) = dir;
               ang = (dir-1)*((2*pi)/P.snoisedirs);
               o.hNoise(3,kk) = (P.snoisespeed / S.frameRate) * cos(ang);
               o.hNoise(4,kk) = (P.snoisespeed / S.frameRate) * sin(ang);
               life = mod(kk, P.snoiselife);
               o.hNoise(6,kk) = life;
               %***********
           end      
           %************
       end
       %**********************************************************
       
    end
   
    function closeFunc(o),
        o.Faces.CloseUp();
        for kk = 1:o.probeNum
           o.hProbe{kk}.CloseUp();
        end
        if (iscell(o.hNoise))
          for kk = 1:o.noiseNum
            if ~isempty(o.hNoise{kk})
               o.hNoise{kk}.CloseUp();
            end
          end
        end
    end
   
    function generate_trialsList(o,S,P)
            % Call a function outside class (easier for us to edit)
            o.trialsList = [];  %all random for this one
    end
        
    %******** given an item number, reset the probe location, ori, and
    %******** its texture for future graphics
    function reset_probe_location_and_texture(o,firstime)
        %******** store target info (will need memory for PR struct)
        oldPos = o.PosList;
        if (firstime)
          anga = 2 * pi * rand;
          newvec = [cos(anga) sin(anga)];
        else
          newvec = -oldPos / norm(oldPos);  %unit vector away from old loc
          anga = -(pi/2) + (pi*rand);
          newvec = [[cos(anga) sin(anga)];[-sin(anga) cos(anga)]] * newvec';
        end
        o.PosList(1) = newvec(1) * o.P.stimEcc;
        o.PosList(2) = newvec(2) * o.P.stimEcc; 
        %******** try using moving targets (more interesting for animal?)
        oldvec = o.PosList - oldPos;
        newvec = oldvec / norm(oldvec);
        anga = -(pi/2) + (pi*rand);  % bias to be moving away from current loc
        newvec = [[cos(anga) sin(anga)];[-sin(anga) cos(anga)]] * newvec';
        o.MovList(1) = newvec(1) * o.MovStep;
        o.MovList(2) = newvec(2) * o.MovStep;
        %*****
        o.FixTime = 0;   % either zero, or time first fixated
        if o.oriNum > 2
          o.targOri = randi((o.oriNum-1));   % integer of ori, 1 to orinum
        else
          o.targOri = randi(o.oriNum);
        end
        o.hProbe{o.targOri}.position = [(o.S.centerPix(1) + round(o.PosList(1)*o.S.pixPerDeg)),...
                                        (o.S.centerPix(2) - round(o.PosList(2)*o.S.pixPerDeg))];
        %**************
    end
    
    function P = next_trial(o,S,P);
          %********************
          o.S = S;
          o.P = P;
          o.error = 0;
          o.FrameCount = 0;
          o.PFrameCount = 0;
          %********
          if (P.trialdur < 20)
              o.TrialDur = P.trialdur;
          else
              o.TrialDur = 20;
          end
          %*************
          o.FixCount = 0;
          o.FixMax = floor( o.TrialDur * 3 );
          o.FixHit = nan(2,o.FixMax);
          o.noiseStim = 0;  % start 0 by default
          %***********
          o.rewardTime = 0;
          o.rewardGap = 0;
          %*******************
          
          % Make Gabor stimulus textures and position them somewhere random
          o.PosList = zeros(1,2); 
          o.MovList = zeros(1,2); 
          o.MovStep = (o.P.stimSpeed / o.S.frameRate);  % in degs for now
          o.FixTime = 0; 
          %********* location and orientation specific params
          o.reset_probe_location_and_texture(1)
    end
    
    function [FP,TS] = prep_run_trial(o)
            % Flags that control transitions
            % State is the main variable to control transitions. A protocol can be
            % described by shifting through states. For this protocol:
            % State 0 -- Foraging for targets
            % State 1 -- Fixation entered on target
            % State 2 -- Rewards for target, face shown
            % State 3 -- Foraging finished
            o.state = 0;
            % Errors describe why a trial was not completed
            % No possible errors for this type of experiment
            o.error = 0;
            % rewardCount counts the number of juice pulses, 1 delivered per frame
            o.rewardCount = 0;
            
            %******* Plot States Struct (show fix in blue for eye trace)
                      % any special plotting of states, 
                      % FP(1).states = 1:2; FP(1).col = 'b';
                      % would show states 1,2 in blue for eye trace
            FP(1).states = 1;  %before fixation
            FP(1).col = 'b-';
            FP(2).states = 2;  % fixation held
            FP(2).col = 'r';
            FP(3).states = 3;  % reward on target  
            FP(3).col = 'g';
            %***********
            TS = 1:3;  % most states are time sensitive due to revcor
            %****************
            o.startTime = GetSecs;
            o.Iti = o.P.iti;  % default ITI, could be longer if error        
    end
    
    function updateNoise(o,xx,yy,currentTime)
         if (o.FrameCount < o.MaxFrame)  
            %*************** 
            if (o.noisetype == 1) 
                kk = 0;
                if (rand < o.P.probNoise)  % fraction of grating noise impulses
                   kk = randi(o.noiseNum);
                   if ~isnan(xx) && ~isnan(yy)
                      o.hNoise{kk}.position = [(o.S.centerPix(1) + round(xx*o.S.pixPerDeg)),(o.S.centerPix(2) - round(yy*o.S.pixPerDeg))];
                   else
                      o.hNoise{kk}.position = o.S.centerPix; 
                   end    
                   o.hNoise{kk}.beforeFrame();
                end
                %**********
                o.FrameCount = o.FrameCount + 1;
                % NOTE: store screen time in "continue_run_trial" after flip
                o.NoiseHistory(o.FrameCount,2) = kk;  % store orientation number
                %**********
            end
            %**************
            if (o.noisetype == 2)
                 %******** select random locations in noise circle and draw
                 nlist = zeros(1,2*o.noiseNum);
                 for kk = 1:o.noiseNum
                     sx = (rand - 0.5) * 2 * o.P.snoisewidth;
                     sy = (rand - 0.5) * 2 * o.P.snoiseheight;
                     nlist(1,1+(kk-1)*2) = sx;
                     nlist(1,2+(kk-1)*2) = sy;
                     %***********
                     if mod((kk-1),2)
                         col = 127 - o.P.range;
                     else
                         col = 127 + o.P.range;
                     end
                     position = [(o.S.centerPix(1) + round(sx*o.S.pixPerDeg)),...
                                 (o.S.centerPix(2) - round(sy*o.S.pixPerDeg))];
                     r = round((o.P.snoisediam/2)*o.S.pixPerDeg);
                     rect = kron([1,1],position) + kron(r(:),[-1, -1, +1, +1]);
                     Screen('FillOval',o.winPtr,[col,col,col],rect');
                     %**************
                 end
                 %*********
                 o.FrameCount = o.FrameCount + 1;
                 o.NoiseHistory(o.FrameCount,:) = [NaN nlist];  % first element time, others x,y positions
                 %********** 
            end
            %**************
            if (o.noisetype == 3) 
                kk = 0;
                step = mod(o.FrameCount,(o.P.noisedur + o.P.noiseoff));
                if (step >= o.P.noiseoff)
                   kk = 1;
                   if ~isnan(xx) && ~isnan(yy)
                      o.hNoise{kk}.position = [(o.S.centerPix(1) + round(xx*o.S.pixPerDeg)),(o.S.centerPix(2) - round(yy*o.S.pixPerDeg))];
                   else
                      o.hNoise{kk}.position = o.S.centerPix; 
                   end    
                   o.hNoise{kk}.beforeFrame();
                end
                %**********
                o.FrameCount = o.FrameCount + 1;
                % NOTE: store screen time in "continue_run_trial" after flip
                o.NoiseHistory(o.FrameCount,2) = kk;  % store orientation number
                %**********
            end
            %****************
            %*************** 
            if (o.noisetype == 4) 
                kk = 0;
                cycle = mod( o.FrameCount, o.P.totCycle );
                if (cycle == 1)  % set new target
                    kk = randi(o.noiseNum);  %positive value onset
                    o.noiseStim = kk;
                end
                if (cycle <= o.P.stimCycle)
                   if (o.noiseStim > 0) 
                       o.hNoise{o.noiseStim}.beforeFrame();
                   end
                else
                   if (o.noiseStim > 0)
                       kk = -o.noiseStim;  % negative value for offset
                       o.noiseStim = 0;  % defines if off
                   end
                end
                %**********
                o.FrameCount = o.FrameCount + 1;
                % NOTE: store screen time in "continue_run_trial" after flip
                o.NoiseHistory(o.FrameCount,2) = kk;  % store orientation number
                %**********
            end
            %***************
            if (o.noisetype == 5)  
                %***** update positions for motion
                nlist = zeros(1,(o.noiseNum * 4)); 
                for kk = 1:o.noiseNum
                   o.hNoise(6,kk) = o.hNoise(6,kk) + 1;
                   if (o.hNoise(6,kk) > o.P.snoiselife)
                       o.hNoise(6,kk) = 1;  % start new
                       sx = (rand - 0.5) * 2 * o.P.snoisewidth;
                       sy = (rand - 0.5) * 2 * o.P.snoiseheight;
                       o.hNoise(1,kk) = sx;
                       o.hNoise(2,kk) = sy;
                       dir = randi(o.P.snoisedirs);
                       o.hNoise(5,kk) = dir;
                       ang = (dir-1)*((2*pi)/o.P.snoisedirs);
                       o.hNoise(3,kk) = (o.P.snoisespeed / o.S.frameRate) * cos(ang);
                       o.hNoise(4,kk) = (o.P.snoisespeed / o.S.frameRate) * sin(ang);
                   else
                       o.hNoise(1,kk) = o.hNoise(1,kk) + o.hNoise(3,kk);
                       o.hNoise(2,kk) = o.hNoise(2,kk) + o.hNoise(4,kk);
                   end
                   %******* build info to store stim info
                   ikk = (kk-1)*4;
                   nlist(1,1+ikk) = o.hNoise(1,kk);
                   nlist(1,2+ikk) = o.hNoise(2,kk);
                   nlist(1,3+ikk) = o.hNoise(5,kk);
                   nlist(1,4+ikk) = o.hNoise(6,kk);
                   %********************
                end
                %****** plot dots
                for kk = 1:o.noiseNum
                     sx = o.hNoise(1,kk);
                     sy = o.hNoise(2,kk);
                     col = 127 + o.P.range;
                     position = [(o.S.centerPix(1) + round(sx*o.S.pixPerDeg)),...
                                 (o.S.centerPix(2) - round(sy*o.S.pixPerDeg))];
                     r = round((o.P.snoisediam/2)*o.S.pixPerDeg);
                     rect = kron([1,1],position) + kron(r(:),[-1, -1, +1, +1]);
                     Screen('FillOval',o.winPtr,[col,col,col],rect');
                     %**************
                end
                %*********
                o.FrameCount = o.FrameCount + 1;
                o.NoiseHistory(o.FrameCount,:) = [NaN nlist];  % first element time, others x,y positions
                %********** 
            end
         end
    end    
    
    function [drop,faceitem] = updateProbes(o,xx,yy,currentTime)
        %**********
        drop = 0;  % none were fixated
        faceitem = 0; % default, none are rewarded
        %***********
        if (o.state > 0)
            %******* if motion, update probe position
            if (o.MovStep > 0)
                newPos = o.PosList + o.MovList;
                if (abs(newPos(1)) > o.P.stimBound)
                      o.MovList(1) = -o.MovList(1); 
                end
                if (abs(newPos(2)) > o.P.stimBound)
                      o.MovList(2) = -o.MovList(2);
                end
                o.PosList = newPos;
                %****** recompute position in pixel coordinates
                o.hProbe{o.targOri}.position = [(o.S.centerPix(1) + round(newPos(1)*o.S.pixPerDeg)),...
                                                (o.S.centerPix(2) - round(newPos(2)*o.S.pixPerDeg))];
                if (o.state == 3)
                    o.Faces.position = o.hProbe{o.targOri}.position;
                end
                %***************************
            end
        end
        if (o.state == 1)  % if state == 2 or 3, then no stim visible to check
            %**********************************************************
            itfix = 0;
            %****** determine if item is fixated
            dist = norm( o.PosList - [xx,yy]);
            if (dist < o.P.fixRadius)
               itfix = 1;
               %****** change probe to be Gaussian, indicate it is fixated
               if (o.FixTime == 0)
                 o.hProbe{o.oriNum}.position = o.hProbe{o.targOri}.position;
                 o.targOri = o.oriNum;
               end
               %*****
            else
               %****** check if hold on item is broken, if so jump new targ
               if ( o.FixTime > 0)
                      %**********
                      o.reset_probe_location_and_texture(0); % make it jump, firstime=1
                      o.FixTime = 0;  % reset, they broke fixation
                      %**********
               end
               %***************
            end
            %****** if an item is fixated, do something
            if (itfix > 0)
                if ~o.FixTime  %first detection, set the time
                    o.FixTime = currentTime;
                else
                   if ( (currentTime - o.FixTime) > o.P.holdDur )
                         drop = 1;  % give reward
                         faceitem = itfix;  %run face stimulus indep of probe
                         %**** record where the fixation occured for eye display
                         if (o.FixCount < o.FixMax)
                             o.FixCount = o.FixCount + 1;
                             o.FixHit(:,o.FixCount) = o.PosList;
                         end
                         %**************
                         o.Faces.imagenum = randi(length(o.Faces.tex));  % pick any at random
                         o.Faces.position = o.hProbe{o.targOri}.position; % set at face at target 
                         %**********
                         o.reset_probe_location_and_texture(0); % make it jump, firstime=1
                         o.FixTime = 0;  % reset item to zero
                         %***********
                   end
                end
            end
        end
        %****** store probe information
        if (o.PFrameCount < o.MaxFrame)
            o.PFrameCount = o.PFrameCount + 1;
            if (drop == 1)  % will be moving to state 2 or 3
                   o.ProbeHistory(o.PFrameCount,1) = NaN;
                   o.ProbeHistory(o.PFrameCount,2) = NaN;
                   o.ProbeHistory(o.PFrameCount,3) = 0;  % intermediate at drop          
            else
                if (o.state < 2)
                   o.ProbeHistory(o.PFrameCount,1) = o.PosList(1);
                   o.ProbeHistory(o.PFrameCount,2) = o.PosList(2);
                   o.ProbeHistory(o.PFrameCount,3) = o.targOri;
                else
                   if (o.state == 3)
                      o.ProbeHistory(o.PFrameCount,1) = NaN;  % not being shown
                      o.ProbeHistory(o.PFrameCount,2) = NaN;
                      o.ProbeHistory(o.PFrameCount,3) = -1;   %indicates face
                   else
                      o.ProbeHistory(o.PFrameCount,1) = NaN;  % not being shown
                      o.ProbeHistory(o.PFrameCount,2) = NaN;
                      o.ProbeHistory(o.PFrameCount,3) = NaN; 
                   end
                end
            end
            % NOTE: store screen time in "continue_run_trial" after flip
        end
        %*******************************
    end
    
    function keepgoing = continue_run_trial(o,screenTime)
        keepgoing = 0;
        if (o.state < 4)
            keepgoing = 1;
        end
        %******** this is also called post-screen flip, and thus
        %******** can be used to time-stamp any previous graphics calls
        %******** for object on the screen and things like that
        if (o.FrameCount)
           o.NoiseHistory(o.FrameCount,1) = screenTime;  %store screen flip 
        end
        if (o.PFrameCount)
           o.ProbeHistory(o.PFrameCount,4) = screenTime;     
        end
        %**** if a stimulus needs post-frame updating
        if (o.noisetype == 4)
            if (o.noiseStim > 0)
              o.hNoise{o.noiseStim}.afterFrame;
            end
        end
        %******************************************************
    end
   
    %******************** THIS IS THE BIG FUNCTION *************
    function drop = state_and_screen_update(o,currentTime,x,y) 
        drop = 0;
        %******* THIS PART CHANGES WITH EACH PROTOCOL ****************
        if (o.state == 0)
            o.state = 1;  % jump in and plot eye traces
        end
        if currentTime > o.startTime + o.TrialDur
            o.state = 4;  % time to end trial
            o.itiStart = GetSecs;
        end
        %***********************
        
        % ALWAYS UPDATE BACKGROUND
        o.updateNoise(NaN,NaN,currentTime);
        % ALWAYS UPDATE THE PROBES
        [drop,faceitem] = o.updateProbes(x,y,currentTime);
        %****** update state by reward events
        if (drop)
            o.rewardTime = currentTime;
            rn = rand;
            o.rewardGap = o.P.mingap + rn * (o.P.maxgap - o.P.mingap);
            if (rn > (1-o.P.probFace))
                o.state = 3;
                if (o.faceTime > o.rewardGap)
                    o.rewardGap = o.faceTime;
                end
            else
                o.state = 2;  % move to a period with no probe target
            end
        end
        %********* update state based on reward timing
        if (o.rewardTime > 0)
            if ( (currentTime - o.rewardTime) > o.rewardGap)
                o.rewardTime = 0;
                o.state = 1;  % show stim again
            else
                if (o.state == 3)  
                    if ( (currentTime - o.rewardTime) > o.faceTime)
                        o.state = 2;  % stop showing face, give extra juice
                        drop = 1;
                    end
                end
            end
        end
        %*******ACTUAL DRAWING OF THE STIMULI *************
        % Draw probe stimuli
        if (o.state < 2)
           o.hProbe{o.targOri}.beforeFrame();  % only one target now
        end
        % Draw face stimulus at probe location and reward at end of display
        if (o.state == 3) 
           o.Faces.beforeFrame(); 
        end
        %****************************************   
    end
    
    function Iti = end_run_trial(o)
        Iti = o.Iti - (GetSecs - o.itiStart); % returns generic Iti interval
    end
    
    function plot_trace(o,handles)
        %****** plot eccentric ring where stimuli appear
        h = handles.EyeTrace;
        set(h,'NextPlot','Replace');
        eyeRad = handles.eyeTraceRadius;
        % Target ring
        r = o.P.stimEcc;
        plot(h,r*cos(0:.01:1*2*pi),r*sin(0:.01:1*2*pi),'-k');
        set(h,'NextPlot','Add');
        %********** plot where all target hits occured
        for k = 1:o.FixCount
           r = o.P.fixRadius;
           xx = o.FixHit(1,k);
           yy = o.FixHit(2,k);
           plot(h,xx + r*cos(0:.01:1*2*pi),yy + r*sin(0:.01:1*2*pi),'-m');
        end
        %*****************
        axis(h,[-eyeRad eyeRad -eyeRad eyeRad]);
    end
    
    function PR = end_plots(o,P,A)   %update D struct if passing back info
        
        %************* STORE DATA to PR
        %**** NOTE, no need to copy anything from P itself, that is saved
        %**** already on each trial in data .... copy parts that are not
        %**** reflected in P at all and generated random per trial
        PR = struct;
        PR.error = o.error;
        if o.FrameCount == 0
            PR.NoiseHistory = [];
            PR.ProbeHistory = [];
        else
            PR.NoiseHistory = o.NoiseHistory(1:o.FrameCount,:);
            PR.ProbeHistory = o.ProbeHistory(1:o.PFrameCount,:);
        end
        PR.spatoris = o.spatoris;  % constant over trials, but still nice to store
        PR.spatfreqs = o.spatfreqs; % constant, but I want to store them
        PR.noisetype = o.noisetype; % store just in case (have in P also)
        PR.noiseNum = o.noiseNum; %differs based on noise type
        %******* need to add a History for probe stimuli later
        
        %******* this is also where you could store Gabor Flash Info
        
        %%%% Record some data %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%% It is advised not to store things too large here, like eye movements, 
        %%%% that would be very inefficient as the experiment progresses
        o.D.error(A.j) = o.error;   % need to decide on something later
        
        %%%% Plot results %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Nothing for now ...
       
    end
    
  end % methods
    
end % classdef
