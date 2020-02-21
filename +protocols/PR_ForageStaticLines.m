classdef PR_ForageStaticLines < protocols.protocol
  % Forage protocol with procedural background noise
  %
  % The class constructor can be called with a range of arguments:
  %
 
  properties (Access = public)
       itiStart double = 0;        % start of iti interval
       rewardCount double = 0;     % counter for reward drops
       rewardGap double = 0;       % gap for next target onset
       rewardTime double = 0;      % store time of last reward
  end
      
  properties (Access = private)
    trialsList        % store copy of trial list (not good to keep in S struct)
    
    %********* stimulus structs for use
    Faces             % object that stores face images for use
    faceTime = 0.1    % time for showing face stimulus
    hProbe = []       % object for foraging stimuli
    probeNum = 1      % number of foraging stimuli
    oriNum = 1        % number of oriented textures to draw from for probe
    targOri = 1       % current orientation of target probe
    %********* Background Line Texture
    hNoise = []       % struct that tracks
    imTex = {}        % PTB texture pointers
    imId = 1          % which image is current
    noiseNum = 1      % number of oriented textures
    %******* parameters for Noise History grating stimulus 
    noisetype = 666   % type of background noise stimulus
    NoiseHistory = [] % list of noise frames over trial and their times
    FrameCount = 0    % count noise frames
    ProbeHistory = [] % list of history for probe objects
    PFrameCount = 0   % count probe frames (should be same as noise for now)
    MaxFrame = []     % twenty second maximum
    TrialDur = 0;     % store internally the trial duration (make less than 20)
    %******** parameters for positioning foraging stimuli
    PosList = []      % will be x,y positions of stimuli
    MovList = []      % speed vector if a moving item
    FixTime = 0      % will be duration item is fixated
    MovStep = 0       % vector amplitude motion step if moving probe
    %*******
    FixCount = 0      % count fixation of probe events
    FixHit = []       % list of positions where probe hits occured
    FixMax = 20        % maximum fixations in any trial
    %**********************************
    D struct = struct()        % store PR data for end plot stats, will store dotmotion array
  end
  
  methods (Access = public)
    function o = PR_ForageStaticLines(winPtr)
        o = o@protocols.protocol(winPtr);
    end
    
    function initFunc(o,S,P)
  
       %********** Set-up for trial indexing (required) 
       cors = [0,4];  % count these errors as correct trials
       reps = [1,2];  % count these errors like aborts, repeat
       o.trialsList = [];  % empty for this protocol
       %**********
      
       %******* init Noise History with MaxDuration **************
       o.TrialDur = P.trialdur;
       o.MaxFrame = ceil(o.TrialDur*S.frameRate);
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
              if (kk == 1)
                 o.hProbe{kk}.orientation = P.prefori;
              else
                 o.hProbe{kk}.orientation = P.nonprefori;
                 o.hProbe{kk}.cpd = P.noncpd;
              end
              %o.hProbe{kk}.orientation = (kk-1)*180/(o.oriNum-1);
              %o.hProbe{kk}.orientation = o.hProbe{kk}.orientation + P.prefori;
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
       
       switch o.noisetype
           
           %***************************************************************
           % for o.noisetype == 0 would be no background at all!
           case 666 % no background
               o.noiseNum = 1;
               [~, ~] = Screen('BlendFunction', o.winPtr, GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
               
               numConds = numel(P.lightBarWidths);
               
               o.hNoise = repmat(struct('dims', S.screenRect(3:4), ...
                   'lightWidth', [], ...
                   'darkWidth', [], ...
                   'start', [], ...
                   'orientation', []), numConds, 1);
               
               o.imTex = cell(numConds,1);
               for iCond = 1:numConds
                o.hNoise(iCond).lightWidth = P.lightBarWidths(iCond);
                o.hNoise(iCond).darkWidth = P.darkBarWidths(iCond);
                o.hNoise(iCond).orientation = P.orientation(iCond);
                o.hNoise(iCond).start = P.startPhase(iCond);
                
                I = buildLineTexture(o.hNoise(iCond));
                
                I = (I - .5) * P.linesContrast * 255 + S.bgColour;
                
                % build texture
                I = uint8(repmat(I, 1, 1, 3));
                o.imTex{iCond} = Screen('MakeTexture', o.winPtr, I);
               end
               
       end
       %**********************************************************
       
    end
   
    function closeFunc(o)
        o.Faces.CloseUp();
        for kk = 1:o.probeNum
           o.hProbe{kk}.CloseUp();
        end
        if iscell(o.noiseNum) % backwards compatible with old-style noise
            for kk = 1:o.noiseNum
                if ~isempty(o.hNoise{kk})
                    o.hNoise{kk}.CloseUp();
                end
            end
        elseif isa(o.hNoise, 'stimuli.stimulus')
            o.hNoise.CloseUp();
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
    
    function P = next_trial(o,S,P)
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
            
            
            % sample which image to show
            o.imId = randi(numel(o.hNoise));
            

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
             
             switch o.noisetype
                     
                 case 666 % static line texture 
                     
                     Screen('DrawTexture', o.winPtr, o.imTex{o.imId});
                     % reset old blend function
%                     Screen('BlendFunction', o.winPtr, sourceFactorOld, destinationFactorOld);
                     %**********
                     o.FrameCount = o.FrameCount + 1;
                     % NOTE: store screen time in "continue_run_trial" after flip
                     o.NoiseHistory(o.FrameCount,2) = o.imId;  % store orientation number
                     %**********
                 
             end
            %****************
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
                      o.ProbeHistory(o.PFrameCount,1) = NaN;
                      o.ProbeHistory(o.PFrameCount,2) = NaN;
                      o.ProbeHistory(o.PFrameCount,3) = -o.Faces.imagenum;   %indicates face
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
        %******************************************************
    end
   
    %******************** THIS IS THE BIG FUNCTION *************
    function drop = state_and_screen_update(o,currentTime,x,y) 
        disp([o.state currentTime-o.startTime o.TrialDur])
        drop = 0; % initialize
        
        %******* THIS PART CHANGES WITH EACH PROTOCOL ****************
        if (o.state == 0)
            o.state = 1;  % jump in and plot eye traces
        end
        if currentTime > o.startTime + o.TrialDur
            o.state = 4;  % time to end trial
            o.itiStart = GetSecs;
            return
        end
        %***********************
        
        % ALWAYS UPDATE BACKGROUND
        o.updateNoise(NaN,NaN,currentTime);
        
        % ALWAYS UPDATE THE PROBES
        [drop,faceitem] = o.updateProbes(x,y,currentTime); %#ok<ASGLU>
        
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
        
%         Screen('DrawingFinished', o.winPtr);
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
        if isa(o.hNoise, 'stimuli.stimulus')
            PR.hNoise = copy(o.hNoise); % store noise object
        elseif isstruct(o.hNoise)
            PR.hNoise = o.hNoise; % let's see how big this gets
        end
        
        PR.error = o.error;
        if o.FrameCount == 0
            PR.NoiseHistory = [];
            PR.ProbeHistory = [];
        else
            PR.NoiseHistory = o.NoiseHistory(1:o.FrameCount,:);
            PR.ProbeHistory = o.ProbeHistory(1:o.PFrameCount,:);
        end
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
  
  methods (Static)
      
      function [Probe, Faces] = regenerateProbes(P,S)
          %******* init reward face for correct trials

          Faces = stimuli.gaussimages(0,'bkgd',S.bgColour,'gray',false);   % color images
          Faces.loadimages('MarmosetFaceLibrary.mat');
          Faces.position = [0,0]*S.pixPerDeg + S.centerPix;
          Faces.radius = round(P.faceradius*S.pixPerDeg);
          Faces.imagenum = 1;  % start first face
          Faces.transparency = -1;  % blend into background
          
          %***** create a Gabor target grating
          oriNum = P.orinum;
          Probe = cell(1,oriNum);
          for kk = 1:oriNum
              %*******
              Probe{kk} = stimuli.grating(0);  % grating probe
              Probe{kk}.transparent = -P.probecon;  % blend in proportion to gauss
              Probe{kk}.gauss = true;
              Probe{kk}.pixperdeg = S.pixPerDeg;
              Probe{kk}.radius = round(P.proberadius*S.pixPerDeg);
              
              Probe{kk}.range = P.proberange;
              Probe{kk}.square = false;
              Probe{kk}.bkgd = P.bkgd;
              %**************
              Probe{kk}.position = [S.centerPix(1),S.centerPix(2)];
              Probe{kk}.phase = P.phase;
              Probe{kk}.cpd = P.cpd;
              if (kk < oriNum)
                  if (kk == 1)
                      Probe{kk}.orientation = P.prefori;
                  else
                      Probe{kk}.orientation = P.nonprefori;
                      Probe{kk}.cpd = P.noncpd;
                  end
                  
              else
                  Probe{kk}.orientation = 0;
                  Probe{kk}.cpd = 0;
                  Probe{kk}.phase = 0;
              end
              %**************
              Probe{kk}.updateTextures();
              %****************
          end
          
          
      end
  end
    
end % classdef
