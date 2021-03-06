library(tidyverse)
library(lubridate)
library(ggthemes)

# load todd's subway_data
load(file = "../../data/todd_subway_realtime.RData")

# load stop_times from GTFS Static
stop_times <- read_csv("../../data/google_transit_subway_static/stop_times.txt")

# load station_data from mta
station_data <- read_csv("http://web.mta.info/developers/data/nyct/subway/Stations.csv")

# get stop_id and stop_name fields, and create a stop_id with N and S appended
station_data <- station_data %>% group_by(`GTFS Stop ID`, `Stop Name`) %>%
  select(stop_id = `GTFS Stop ID`, stop_name = `Stop Name`) %>%
  mutate(stop_id_N = sprintf('%sN', stop_id), stop_id_S = sprintf('%sS', stop_id)) %>%
  gather(`stop_id_N`, `stop_id_S`, key = "stop_ids", value = "stop_id") %>%
  select(stop_name, stop_id)

################################################################################
# Getting Station Information
################################################################################
# Generate edges between stations
trips <- stop_times %>% extract(trip_id, "route", regex=".*_.*_(.*)\\.\\..*", remove = FALSE)
trip_edges <- trips %>% mutate(prev_stop_id = ifelse(lag(trip_id) == trip_id, lag(stop_id), NA))
edges <- trip_edges %>% select(route, stop_id, prev_stop_id) %>% distinct()
# create stations dataframe with line, stop_id, stop_name
stations <- edges %>% left_join(station_data, by = c("stop_id"="stop_id")) %>% select(line=route, stop_id, stop_name)

################################################################################
# Express vs Local Train Distribution Plot Function
################################################################################
# How the function works:
#   Filter through all local and express train trips between two stations. 
#   Calculate the time between two stations (trip time) for all trip across the day
#   Compare the differences in histogram
# 
# Input for the function:
#   local line, express line (character)
#   Stop ID (start, end) must include direction (S,N)
#   Stop ID can be match with stop name via station_data dataframe

# Helper Function to Determine if Day is Weekend
isWeekend <- function(day_of_week) {
  ifelse(day_of_week == "Saturday" | day_of_week == "Sunday", T, F)
}

stops <- stations %>%
  filter(line == "1", grepl(sprintf("%s$", "S"), stop_id)) %>%
  unique()

# find trip time during 96th station and 14th station

plot_local_express <- function(local_line, express_line, start_stop_id, end_stop_id)
{
  # local train
  local_train <- subway_data %>%
    filter(stop_mta_id == start_stop_id | stop_mta_id == end_stop_id,
           route_mta_id == local_line) %>%
    mutate(day_of_week = weekdays((departure_time)),
           hour = hour(departure_time)) %>%
    filter(isWeekend(day_of_week) == F, hour > 6, hour < 20) %>%
    left_join(stops, by = c("stop_mta_id" = "stop_id")) %>%
    group_by(realtime_trip_id) %>% 
    arrange(desc(departure_time)) %>%
    mutate(diff = (first(departure_time) - last(departure_time))/60)
  
  # plot for local line
  plot_local <- local_train %>%
    ggplot(aes(x=diff)) + geom_histogram()
  
  # express train
  express_train <- subway_data %>%
    filter(stop_mta_id == start_stop_id | stop_mta_id == end_stop_id,
           route_mta_id == express_line) %>%
    mutate(day_of_week = weekdays(departure_time),
           hour = hour(departure_time)) %>%
    filter(isWeekend(day_of_week) == F, hour > 6, hour < 20) %>%
    left_join(stops, by = c("stop_mta_id" = "stop_id")) %>%
    group_by(realtime_trip_id) %>%
    arrange(desc(departure_time)) %>%
    mutate(diff = (first(departure_time) - last(departure_time))/60)
  
  # plot for express train
  plot_express <- express_train %>%
    ggplot(aes(x=diff)) + geom_histogram()
  
  # code for combining plots as per: https://stackoverflow.com/questions/21192002/how-to-combine-2-plots-ggplot-into-one-plot
  local_train$group <- "local"
  express_train$group <- "express"
  
  combined <- rbind(local_train, express_train)
  
  combined_plot <- ggplot(combined, aes(x=diff, group=group, col=group, fill=group)) +
    geom_histogram(alpha = 0.8, position = "identity")
  # NOTE: can get intersecting distributions by running the code below 
  # geom_density(alpha = 0.8, position = "identity")
  
  return(combined_plot)
}

plot_local_express ("1", "2", "120S", "132S")