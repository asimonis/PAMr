#' @title Load and Process Detections from Pamguard
#'
#' @description Loads in acoustic detection data that has been run thorugh
#'   Pamguard. Uses the binary file output from Pamguard and (optionally)
#'   the database used. If a database is used then only detections found
#'   in that database will be processed, and they will be grouped by either
#'   the 'OfflineEvents' table or the 'Detection Group Localiser' module
#'   groups. If no database is provided, all detections in all of the
#'   provided binary files will be processed, this can take an extremely
#'   long time. This will also apply a set of functions to the binaray data
#'   loaded. \code{getPgDetections} is just a wrapper that will call
#'   either \code{getPgDetectionsAll} or \code{getPgDetectionsDb} based
#'   on whether or not a database file is provided.
#'
#' @param prs a \linkS4class{PAMrSettings} object containing the databases,
#'   binaries, and functions to use for processing data.
#'   See \code{\link[PAMr]{PAMrSettings}}
#' @param sampleRate the sample rate of the data. If reading detections from
#'   a database this will be read in from the SoundAcquisition table, if
#'   loading all binary files this must be specified.
#' @param grouping if reading from a database, the table to group events by.
#'   Either \code{event} to use the OfflineEvents table, or \code{detGroup} to
#'   use the detection group localiser module groups.
#' @param \dots other parameters to be passed on to other methods
#'
#' @return a list of \linkS4class{AcousticEvent} objects. If reading from a
#'   database, there will be a separate AcousticEvent for each event found
#'   by the grouping method chosen. If just reading all detections in a set
#'   of binary files, all the detections will be in a single AcousticEvent.
#'
#' @author Taiki Sakai \email{taiki.sakai@@noaa.gov}
#'
#' @importFrom PamBinaries loadPamguardBinaryFile
#' @importFrom PAMmisc squishList
#' @importFrom RSQLite dbConnect dbListTables dbReadTable dbDisconnect SQLite
#' @importFrom stringr str_trim
#' @importFrom data.table data.table setkey
#' @importFrom purrr transpose
#' @import dplyr
#' @export
#'
getPgDetections <- function(prs, ...) {
    if(class(prs) != 'PAMrSettings') {
        stop(paste0(prs, ' is not a PAMrSettings object. Please create one with',
                    ' function "PAMrSettings()"'))
    }
    if(length(prs@db)==0) {
        return(getPgDetectionsAll(prs, ...))
    }
    getPgDetectionsDb(prs, ...)
}

#' @rdname getPgDetections
#' @importFrom utils setTxtProgressBar txtProgressBar
#' @export
#'
getPgDetectionsAll <- function(prs, sampleRate) {
    if(class(prs) != 'PAMrSettings') {
        stop(paste0(prs, ' is not a PAMrSettings object. Please create one with',
                    ' function "PAMrSettings()"'))
    }
    binList <- prs@binaries$list
    binFuns <- prs@functions
    if(missing(sampleRate)) {
        sampleRate <- readline(prompt =
                                   paste0('What is the sample rate for this data? ',
                                          '(When processing all binaries, sample rate must be the same) '))
        sampleRate <- as.numeric(sampleRate)
    }
    calibrationUsed <- 'None'
    cat('Processing binary files... \n')
    pb <- txtProgressBar(min=0, max=length(binList), style=3)

    binData <- lapply(binList, function(bin) {
        thisBin <- loadPamguardBinaryFile(bin)
        for(i in seq_along(thisBin$data)) {
            thisBin$data[[i]]$sampleRate <- sampleRate
        }
        thisBinData <- calculateModuleData(thisBin, binFuns)
        setTxtProgressBar(pb, value=which(binList==bin))
        thisBinData
    })
    binData <- binData[sapply(binData, function(x) !is.null(x))]
    binData <- lapply(binData, function(x) split(x, x$detectorName))
    binData <- unlist(binData, recursive = FALSE)
    binData <- squishList(binData)

    # Should this function store the event ID? Right now its just the name
    # in the list, but is this reliable? Probably not

    acousticEvents <- AcousticEvent(detectors = binData, settings = DataSettings(sampleRate = sampleRate),
                                    files = list(binaries=basename(binList), database='None', calibration=calibrationUsed))
    acousticEvents
}

#' @rdname getPgDetections
#' @export
#'
getPgDetectionsDb <- function(prs, grouping=c('event', 'detGroup')) {
    if(class(prs) != 'PAMrSettings') {
        stop(paste0(prs, ' is not a PAMrSettings object. Please create one with',
                    ' function "PAMrSettings()"'))
    }
    db <- prs@db
    binList <- prs@binaries$list
    binFuns <- prs@functions
    dbData <- getDbData(db, grouping)
    thisSr <- unique(dbData$sampleRate)
    if(length(thisSr) > 1) {
        warning('More than 1 sample rate found in database ',
                basename(db),'.')
    }
    thisSource <- unique(dbData$SystemType)
    dbData <- select(dbData, -SystemType)
    calibrationUsed <- 'None'

    dbData <- lapply(
        split(dbData, dbData$BinaryFile), function(x) {
            thisBin <- getBinaryData(x, binList)
            if(length(thisBin)==0) {
                warning('Could not find the matching binary file for ', x$BinaryFile[1],
                        ' in database ', basename(x))
                return(NULL)
            }
            binData <- calculateModuleData(thisBin, binFuns) %>%
                select(-BinaryFile)
            left_join(x, binData, by='UID') %>% distinct()
        })

    # This is a list for each binary, we want for each detector
    dbData <- dbData[sapply(dbData, function(x) !is.null(x))]

    dbData <- lapply(dbData, function(x) split(x, x$detectorName))
    names(dbData) <- NULL
    dbData <- unlist(dbData, recursive = FALSE)
    dbData <- squishList(dbData)

    # Split into events, then swap from Detector(Events) to Event(Detectors)
    # .names necessary to make sure we have all event numbers
    dbData <- transpose(
        lapply(dbData, function(x) split(x, x$parentUID)),
        .names = unique(unlist(sapply(dbData, function(x) x$parentUID)))
    )

    # Should this function store the event ID? Right now its just the name
    # in the list, but is this reliable? Probably not

    acousticEvents <- lapply(dbData, function(ev) {
        ev <- ev[sapply(ev, function(x) !is.null(x))]
        binariesUsed <- sapply(ev, function(x) unique(x$BinaryFile)) %>%
            unlist(recursive = FALSE) %>% unique()
        AcousticEvent(detectors = ev, settings = DataSettings(sampleRate = thisSr, soundSource=thisSource),
                      files = list(binaries=binariesUsed, database=basename(db), calibration=calibrationUsed))
    })
    acousticEvents
}

getDbData <- function(db, grouping=c('event', 'detGroup')) {
    # Combine all click/event tables, even by diff detector. Binary will have det name
    con <- dbConnect(SQLite(), db)
    tables <- dbListTables(con)
    # Read in event data from either offlineclicks/events or detection
    # group localiser. Click version has common naming convention,
    # det group does not so we have to go look it up. If we are just
    # reading in all the data we only care about SA data
    switch(match.arg(grouping),
           'event' = {
               detTables <- grep('OfflineClicks', tables, value=TRUE)
               eventTables <- grep('OfflineEvents', tables, value=TRUE)
               eventColumns <- c('UID', 'eventType', 'comment')
           },
           'detGroup' = {
               modules <- dbReadTable(con, 'PamguardModules')
               dgTables <- modules %>%
                   mutate(Module_Name=str_trim(Module_Name),
                          Module_Type=str_trim(Module_Type)) %>%
                   filter(Module_Name == 'Detection Group Localiser') %>%
                   distinct(Module_Type, Module_Name)
               dgNames <- gsub(' ',  '_', dgTables$Module_Type)
               detTables <- sapply(dgNames, function(x) grep(x, tables, value=TRUE))
               eventTables <- detTables[!grepl('Children', detTables)]
               detTables <- detTables[grepl('Children', detTables)]
               eventColumns <- c('UID')
           },
           {
               dbDisconnect(con)
               stop("I don't know how to group by ", grouping, '.\n')
           }
    )

    if(length(detTables)==0 ||
       length(eventTables)==0) {
        stop('Could not find tables for grouping method "', grouping,
             '" in database ', basename(db))
    }
    allDetections <- bind_rows(
        lapply(detTables, function(table) {
            dbReadTable(con, table)
        })
    )
    if(nrow(allDetections)==0) {
        stop('No detections found for grouping method "', grouping,
             '" in database ', basename(db))
    }

    allEvents <- bind_rows(
        lapply(eventTables, function(table) {
            dbReadTable(con, table)
        })
    )

    eventColumns <- eventColumns[eventColumns %in% colnames(allEvents)]
    allEvents <- select_(allEvents, .dots=eventColumns)

    allDetections <- left_join(
        allDetections, allEvents, by=c('parentUID'='UID')
    )

    soundAcquisition <- dbReadTable(con, 'Sound_Acquisition') %>%
        mutate(UTC = as.POSIXct(as.character(UTC), format='%Y-%m-%d %H:%M:%OS', tz='UTC'),
               Status = str_trim(Status),
               SystemType = str_trim(SystemType)) %>%
        filter(Status=='Start') %>%
        arrange(UTC) %>%
        select(UTC, sampleRate, SystemType) %>%
        distinct() %>%
        data.table() %>% setkey(UTC)
    dbDisconnect(con)

    allDetections <- allDetections %>%
        mutate(BinaryFile = str_trim(BinaryFile),
               UTC = as.POSIXct(as.character(UTC), format='%Y-%m-%d %H:%M:%OS', tz='UTC')) %>%
        select_(.dots=unique(c(eventColumns, 'UTC', 'Id', 'UID', 'parentUID', 'BinaryFile'))) %>%
        data.table() %>% setkey(UTC)

    # This rolling join rolls to the first time before. Since we filtered to only starts, it goes back
    # to whatever the last Start was.
    allDetections <- soundAcquisition[allDetections, roll = TRUE] %>%
        data.frame()
    srNa <- which(is.na(allDetections$sampleRate))
    if(length(srNa) == nrow(allDetections)) {
        srReplace <- as.integer(
            readline(prompt = 'No Sample Rate found in SoundAcquisition table. Enter Sample Rate for this data:\n')
        )
        allDetections$sampleRate[srNa] <- srReplace
    } else if(length(srNa) > 0) {
        # get mode
        mode <- which.max(tabulate(allDetections$sampleRate[-srNa]))
        srChoice <- menu(title=paste0('Could not get Sample Rate for all detections from the "SoundAcquistion" table.',
                                      ' Should missing values be replaced with ', mode, '(value found in table).'),
                         choices = c('Yes', 'No (I want to enter my own SR)'))
        srReplace <- switch(srChoice,
                            '1' = mode,
                            '2' = readline(prompt='What Sample Rate should be used?\n'),
                            stop('Sample Rate required for calculations.')
        )
        allDetections$sampleRate[srNa] <- srReplace
    }
    allDetections
}

getBinaryData <- function(dbData, binList) {
    dbData <- arrange(dbData, UID)
    # This breaks if 'dbData' doesnt have binaryfile...
    binFile <- dbData$BinaryFile[1]
    allBinFiles <- grep(binFile, binList, value=TRUE)
    if(length(allBinFiles)==0) {
        return(NULL)
    } else if(length(allBinFiles)==1) {
        thisBin <- loadPamguardBinaryFile(allBinFiles, keepUIDs=dbData$UID)
        matchSr <- select(dbData, UID, sampleRate) %>%
            distinct() %>% arrange(UID)
        for(i in seq_along(matchSr$UID)) {
            thisBin$data[[i]]$sampleRate <- matchSr$sampleRate[i]
        }
        return(thisBin)
    } else {
        for(bin in allBinFiles) {
            thisBin <- loadPamguardBinaryFile(bin)
            # We've found the right file if UID is in file
            if(dbData$UID[1] %in% names(thisBin$data)) {
                thisBin$data <- thisBin$data[dbData$ClickNo+1]
                for(i in seq_along(dbData$UID)) {
                    thisBin$data[[i]]$sampleRate <- dbData$sampleRate[i]
                }
                return(thisBin)
            } else {
                next
            }
        }
        # If we made it here we didnt find a matching file
        return(NULL)
    }
}
