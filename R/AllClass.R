## ---- PAMrSettings Class ----------------------------------------------------
#' @title \code{PAMrSettings} Class
#' @description An S4 class that stores settings related to all processing and analysis steps
#' done in PAMr. A PAMrSettings object will be the main input to any major function
#' in the PAMr package.
#'
#' @slot db the full path to a PamGuard database file
#' @slot binaries a list with items "folder" containing the directory of the
#'   PamGuard binary files, and "list" containing the full path to each individual
#'   binary file.
#' @slot functions a named list of functions to apply to data read in by PAMr.
#'   Should be named by the PamGuard module the function should be applied to.
#'   Currently supports "ClickDetector" and "WhistlesMoans".
#' @slot calibration a named list of calibration functions to apply while
#'   applying functions from the "functions" slot. Should named by the
#'   PamGuard module, same as the "functions"
#'
#' @author Taiki Sakai \email{taiki.sakai@@noaa.gov}
#' @export
#'
setClass('PAMrSettings',
         slots = c(
             db = 'character',
             binaries = 'list',
             functions = 'list',
             calibration = 'list'
         ),
         prototype = prototype(
             db = character(0),
             binaries = list('folder'=character(0), 'list'=character(0)),
             functions = list('ClickDetector'=list(), 'WhistlesMoans'=list()),
             calibration = list('ClickDetector'=list())
         )
)

setValidity('PAMrSettings',
            function(object) {
                valid <- TRUE
                if(!all(c('folder', 'list') %in% names(object@binaries))) {
                    valid <- FALSE
                    cat('slot binaries must have items "folder" and "list"\n')
                }
                if(!all(c('ClickDetector', 'WhistlesMoans') %in% names(object@functions))) {
                    valid <- FALSE
                    cat('slot functions must have items "ClickDetector" and "WhistlesMoans"\n')
                }
                valid
            }
)

#' @importFrom utils str
#'
setMethod('show', 'PAMrSettings', function(object) {
    nBin <- length(object@binaries$list)
    nBinDir <- length(object@binaries$folder)
    nDb <- length(object@db)
    nCal <- length(object@calibration$ClickDetector)
    cat('PAMrSettings object with:\n')
    cat(nDb, 'database(s)')
    if(nDb > 0) {
        cat(':\n ', paste(basename(object@db), collapse='\n  '))
    }
    cat('\n', nBinDir, ' binary folder(s) ', sep = '')
    if(nBinDir > 0) {
        cat('containing', nBin, 'binary files\n')
    } else {
        cat('\n')
    }
    # Print function names and args for each module
    for(m in seq_along(object@functions)) {
        cat(length(object@functions[[m]]), ' function(s) for module type "',
            names(object@functions)[m], '"\n', sep = '')
        for(f in seq_along(object@functions[[m]])) {
            cat(' "', names(object@functions[[m]])[f], '"\n  ', sep = '')
            cat(str(object@functions[[m]][[f]]))
        }
    }
    cat(nCal, 'click calibration function(s)\n')
})

## ---- DataSettings Class ----------------------------------------------------
# Data Collection / Array Settings (obj)              \\settings
# Hydro sens, sample rate, whatever. Make an object and we figure out what it needs
#' An S4 class to store data collection settings. Possible inclusions are
#' hydrophone sensitivity, sample rate, sound card, etc.
#'
#' @slot sampleRate the sample rate data was recorded at.
#' @slot soundSource the source of the recorded sound - sound card, recording
#'   system, or sound file
#'
setClass('DataSettings',
         slots = c(
             sampleRate = 'integer',
             soundSource = 'character'
         ),
         prototype = prototype(sampleRate=NA_integer_, soundSource='Not Found')
)

setValidity('DataSettings',
            function(object) {
                TRUE
            }
)

DataSettings <- function(sampleRate=NA_integer_, soundSource='Not Found') {
    if(missing(sampleRate)) {
        warning('"sampleRate" not specified.')
    }
    if(missing(soundSource)) {
        warning('"soundSource" not found.')
    }
    new('DataSettings', sampleRate=as.integer(sampleRate), soundSource=soundSource)
}

setMethod('show', 'DataSettings',
          function(object) {
              sampleRates <- object@sampleRate
              soundSources <- object@soundSource
              if(length(sampleRates) > 6) {
                  sampleRates <- c(sampleRates[1:6], '...')
              }
              if(length(soundSources) > 6) {
                  soundSources <- c(soundSources[1:6], '...')
              }
              sampleRates <- paste(sampleRates, collapse=', ')
              soundSources <- paste(soundSources, collapse=', ')
              cat('DataSettings object with settings:\nSample Rate(s):', sampleRates,
                  '\nSound Source(s):', soundSources)
          }
)


# Were gonna get sampleRate and soundcard system type from SoundAcquisition table sampleRate and SystemType
# Other stuff from a logger form? Iffy..for HICEAS this is split across different fuckiNG DATBASES

## ---- VisObsData Class ------------------------------------------------------
# Visual data (obj)                                   \\visData
# Detection time, spp IDs, group size est, effort status. Multiple ways to read

setClass('VisObsData',
         slots = c(
             detectionTime = 'POSIXct',
             speciesId = 'character',
             groupSizeEst = 'numeric',
             effortStatus = 'character'
         ),
         prototype = prototype(detectionTime = Sys.time(), speciesId = 'None',
                               groupSizeEst = NaN, effortStatus = 'None')
)

setValidity('VisObsData',
            function(object) {
                TRUE
            }
)

# Basic constructor
VisObsData <- function(detectionTime=Sys.time(), speciesId='None',
                       groupSizeEst=NaN, effortStatus='None') {
    new('VisObsData', detectionTime=detectionTime, speciesId=speciesId,
        groupSizeEst=groupSizeEst, effortStatus=effortStatus)
}

## ---- AcousticEvent Class ---------------------------------------------------

# Acoustic event (obj) <--- this is really a list of AcEv? These need an ID for banter \acousticEvents
# Detector - named list [[detector name]] of lists    \\detector
# Data.table of detections w/ id
# possible image
# Localization - named list[[loc. type name]]         \\localization
# Data frame of positions
# Data Collection / Array Settings (obj)              \\settings
# Hydro sens, sample rate, whatever. Make an object and we figure out what it needs
# Visual data (obj)                                   \\visData
# Detection time, spp IDs, group size est, effort status. Multiple ways to read
# Behavioral (lul)                                    \\behavior
# erddap                                               \\erddap
# https://github.com/rmendels/Talks/blob/master/netCDF_Presentation/netcdf_opendap_erddap.Rmd
# Species classification - list of classifier objects \\specClass
# Method, prediction, assignment probabilities
# Duration? Files used? ID?

# Will want to have an assign species method for these. When going from PAMr -> training BANTER
# need a way to mark species by event outside of PAMGuard.
# Could have option to do from OfflineEvent comment or eventType field. Should we read these in
# to start? And somewhat hide them? PITA to go back and find them after, tho I guess we are
# possibly going to save the DB info somewhere. Actually we should definitely save that somewhere.
# Have a 'files used' or some shit with DB and all binary files read to make it

# Or are we doing this at cruise level? seems wrong...
# setClassUnion('VisOrNULL', c('VisObsData', 'NULL'))

#' @title \code{AcousticEvent} Class
#' @description An S4 class storing acoustic detections from an Acoustic Event
#'   as well as other related metadata
#'
#' @slot detectors a list of data frames that have acoustic detctions and
#'   any measurements calculated on those detections. Each data frame is named
#'   by the detector that made the detection
#' @slot localizations a named list storing localizations, named by method
#' @slot settings a \linkS4class{DataSettings} object for this event
#' @slot visData a \linkS4class{VisObsData} with visual data for this event
#' @slot behavior behavior data
#' @slot erddap environmental data
#' @slot specClass a list of species classifications for this event, named by
#'   classification method (ie. BANTER model, visual ID)
#' @slot files a list of files used to create this object, named by the type of
#'   file (ie. binaries, database)
#'
#' @author Taiki Sakai \email{taiki.sakai@@noaa.gov}
#' @export
#'
setClass('AcousticEvent',
         slots = c(
             detectors = 'list',
             localizations = 'list',
             settings = 'DataSettings',
             visData = 'VisObsData',
             behavior = 'list',
             erddap = 'list',
             specClass = 'list',
             files = 'list'),
         prototype = prototype(detectors=list(), localizations=list(), settings=DataSettings(),
                               visData=VisObsData(), behavior=list(), erddap=list(), specClass=list(),
                               files = list())
)

setValidity('AcousticEvent',
            function(object) {
                valid <- TRUE
                if(length(object@detectors)==0) {
                    cat('AcousticEvent object must have at least one detector. \n')
                    valid <- FALSE
                }
                if(is.null(names(object@detectors))) {
                    cat('All detectors in the "detectors" slot must be named. \n')
                    valid <- FALSE
                }
                valid
            }
)
# Basic constructor
AcousticEvent <- function(detectors=list(), localizations=list(), settings=DataSettings(), visData=VisObsData(),
                          behavior=list(), erddap=list(), specClass=list(), files=list()) {
    new('AcousticEvent', detectors=detectors, localizations=localizations, settings=settings,
        visData=visData, behavior=behavior, erddap=erddap, specClass=specClass, files=files)
}

setMethod('show', 'AcousticEvent',
          function(object) {
              cat('AcousticEvent object with', length(object@detectors), 'detector(s): \n')
              cat(paste(names(object@detectors), collapse=', '))
          }
)

## ---- Cruise Class ----------------------------------------------------------
# Cruise class
# Cruise (object)
# Files / folders (dbs, bins, vis, enviro)      \folders
# GPS                                           \gpsData
# Acoustic event (obj) <--- this is really a list of AcEv? These need an ID for banter \acousticEvents
# Detector - named list [[detector name]] of lists    \\detector
# Data.table of detections w/ id
# possible image
# Localization - named list[[loc. type name]]         \\localization
# Data frame of positions
# Data Collection / Array Settings (obj)              \\settings
# Hydro sens, sample rate, whatever. Make an object and we figure out what it needs
# Visual data (obj)                                   \\visData
# Detection time, spp IDs, group size est, effort status. Multiple ways to read
# Behavioral (lul)                                    \\behavior
# erddap                                               \\erddap
# Species classification - list of classifier objects \\specClass
# Method, prediction, assignment probabilities
# Detector settings - named list [[detector name]]   \detectorSettings
# Localization settings - named list [[ loc. type]]  \localizationSettings
# Some effort bullshit                               \effort
# ??????
# ???????

setClass('Cruise',
         slots = c(
             folders = 'list',
             gpsData = 'data.frame',
             acousticEvents = 'list',
             detectorSettings = 'list',
             localizationSettings = 'list',
             effort = 'data.frame'), # maybe
         prototype = prototype(
             folders=list(database='None', binaries='None', visData='None', enviroData='None'),
             gpsData=data.frame(), acousticEvents=list(), detectorSettings=list(),
             localizationSettings=list(), effort=data.frame())
)

setValidity('Cruise',
            function(object) {
                valid <- TRUE
                # This doesnt work if there are none. Required to have some or not?
                if(!all(sapply(object@acousticEvents, function(x) class(x)=='AcousticEvent'))) {
                    cat('Slot acousticEvents must be a list of AcousticEvent objects. \n')
                    valid <- FALSE
                }
                if(!all(names(object@folders) %in% c('database', 'binaries', 'visData', 'enviroData'))) {
                    cat('Slot folders must be a list with names "database", "binaries", "visData", and "enviroData". \n')
                    valid <- FALSE
                }
                # check all detecotrs in acevs are in detectorSettings list
                valid
            }
)

# Constructor
Cruise <- function(folders=list(datbase='None', binaries='None', visData='None', enviroData='None'),
                   gpsData=data.frame(), acousticEvents=list(), detectorSettings=list(),
                   localizationSettings=list(), effort=data.frame()) {
    new('Cruise', folders=folders, gpsData=gpsData, acousticEvents=acousticEvents,
        detectorSettings=detectorSettings, localizationSettings=localizationSettings, effort=effort)
}
