#!/usr/bin/env python3
"""
Lizmap Load Testing Script
This script creates heavy load on the Lizmap software stack by simulating multiple concurrent users
accessing the map interface and waiting for complete rendering.
"""

import asyncio
import time
import logging
from concurrent.futures import ThreadPoolExecutor, as_completed
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.common.exceptions import TimeoutException, WebDriverException
import threading
import random
import os
from datetime import datetime

class LizmapLoadTester:
    def __init__(self, base_url, concurrent_users=5, test_duration=300, headless=True):
        """
        Initialize the load tester
        
        Args:
            base_url (str): The Lizmap project URL to test
            concurrent_users (int): Number of concurrent browser instances
            test_duration (int): Duration of test in seconds
            headless (bool): Run browsers in headless mode
        """
        self.base_url = base_url
        self.concurrent_users = concurrent_users
        self.test_duration = test_duration
        self.headless = headless
        self.results = []
        self.lock = threading.Lock()
        
        # Create screenshots directory
        self.screenshot_dir = "lizmap_load_test_screenshots"
        os.makedirs(self.screenshot_dir, exist_ok=True)
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler('lizmap_load_test.log'),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)

    def create_driver(self):
        """Create a Chrome WebDriver instance with appropriate options"""
        chrome_options = Options()
        if self.headless:
            chrome_options.add_argument("--headless")
        chrome_options.add_argument("--no-sandbox")
        chrome_options.add_argument("--disable-dev-shm-usage")
        chrome_options.add_argument("--disable-gpu")
        chrome_options.add_argument("--window-size=1920,1080")
        chrome_options.add_argument("--disable-extensions")
        chrome_options.add_argument("--disable-plugins")
        chrome_options.add_argument("--disable-images")  # Speed up loading
        
        try:
            driver = webdriver.Chrome(options=chrome_options)
            driver.set_page_load_timeout(60)
            return driver
        except Exception as e:
            self.logger.error(f"Failed to create driver: {e}")
            return None

    def take_screenshot(self, driver, user_id, load_attempt, status="unknown"):
        """
        Take a screenshot of the current browser state
        
        Args:
            driver: WebDriver instance
            user_id: ID of the user session
            load_attempt: Number of this load attempt
            status: Status of the load (success, failed, etc.)
        """
        try:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"user_{user_id}_attempt_{load_attempt}_{status}_{timestamp}.png"
            filepath = os.path.join(self.screenshot_dir, filename)
            
            driver.save_screenshot(filepath)
            self.logger.info(f"Screenshot saved: {filepath}")
            return filepath
        except Exception as e:
            self.logger.error(f"Failed to take screenshot: {e}")
            return None

    def wait_for_map_load(self, driver, timeout=30):
        """
        Wait for the Lizmap map to fully load
        This checks for various indicators that the map has finished rendering
        """
        try:
            # First check if we even get a 200 response by looking for basic page elements
            try:
                page_title = driver.title
                if not page_title or "error" in page_title.lower() or "timeout" in page_title.lower():
                    self.logger.warning(f"Page title suggests error: '{page_title}'")
                    return False
            except:
                self.logger.warning("Could not get page title")
                return False
            
            # Check for common error indicators in page source
            try:
                page_source = driver.page_source.lower()
                if any(error_text in page_source for error_text in [
                    "504 gateway timeout", "502 bad gateway", "503 service unavailable",
                    "connection refused", "internal server error", "nginx"
                ]):
                    self.logger.warning("Found error indicators in page source")
                    return False
            except:
                pass
            
            # Wait for the main map container
            WebDriverWait(driver, timeout).until(
                EC.presence_of_element_located((By.ID, "map"))
            )
            
            # Check if map div actually has content (not just exists)
            map_element = driver.find_element(By.ID, "map")
            if not map_element or map_element.size['height'] < 100:
                self.logger.warning("Map element exists but seems empty or too small")
                return False
            
            # Wait for OpenLayers map initialization
            WebDriverWait(driver, timeout).until(
                lambda d: d.execute_script("return typeof window.lizMap !== 'undefined'")
            )
            
            # Check if lizMap is actually initialized with a map
            lizmap_ready = driver.execute_script("""
                try {
                    return window.lizMap && window.lizMap.map && window.lizMap.map.layers && window.lizMap.map.layers.length > 0;
                } catch(e) {
                    return false;
                }
            """)
            
            if not lizmap_ready:
                self.logger.warning("LizMap object exists but map not properly initialized")
                return False
            
            # Wait for layers to load - check if loading indicator is gone
            WebDriverWait(driver, timeout).until(
                lambda d: not d.find_elements(By.CLASS_NAME, "loading") or 
                         all(not elem.is_displayed() for elem in d.find_elements(By.CLASS_NAME, "loading"))
            )
            
            # Additional check for actual map tiles being loaded
            tiles_loaded = driver.execute_script("""
                try {
                    var map = window.lizMap.map;
                    var layers = map.layers;
                    var tilesLoading = 0;
                    for (var i = 0; i < layers.length; i++) {
                        if (layers[i].loading) tilesLoading++;
                    }
                    return tilesLoading === 0;
                } catch(e) {
                    return true; // If we can't check, assume loaded
                }
            """)
            
            if not tiles_loaded:
                self.logger.warning("Map tiles still loading")
                # Give it a bit more time for tiles
                time.sleep(5)
            
            # Additional wait to ensure all tiles are loaded
            time.sleep(2)
            
            return True
            
        except TimeoutException:
            self.logger.warning(f"Map loading timed out after {timeout} seconds")
            return False
        except Exception as e:
            self.logger.error(f"Error waiting for map load: {e}")
            return False

    def simulate_user_session(self, user_id, session_duration=None):
        """
        Simulate a single user session with map interactions
        
        Args:
            user_id (int): Unique identifier for this user session
            session_duration (int): Duration of this session in seconds
        """
        if session_duration is None:
            session_duration = random.randint(30, 120)  # Random session length
            
        start_time = time.time()
        driver = None
        load_attempt = 0
        session_results = {
            'user_id': user_id,
            'start_time': start_time,
            'page_loads': 0,
            'successful_loads': 0,
            'errors': 0,
            'total_load_time': 0,
            'screenshots': []
        }
        
        try:
            driver = self.create_driver()
            if not driver:
                session_results['errors'] += 1
                return session_results
                
            self.logger.info(f"User {user_id}: Starting session for {session_duration} seconds")
            
            while time.time() - start_time < session_duration:
                load_attempt += 1
                load_start = time.time()
                
                try:
                    # Load the page
                    driver.get(self.base_url)
                    session_results['page_loads'] += 1
                    
                    # Always take a screenshot after page load but before verification
                    screenshot_path = self.take_screenshot(driver, user_id, load_attempt, "after_page_load")
                    if screenshot_path:
                        session_results['screenshots'].append(screenshot_path)
                    
                    # Wait for map to fully load
                    if self.wait_for_map_load(driver):
                        session_results['successful_loads'] += 1
                        load_time = time.time() - load_start
                        session_results['total_load_time'] += load_time
                        
                        # Take screenshot after successful load verification
                        success_screenshot = self.take_screenshot(driver, user_id, load_attempt, "success")
                        if success_screenshot:
                            session_results['screenshots'].append(success_screenshot)
                        
                        self.logger.info(f"User {user_id}: Map loaded successfully in {load_time:.2f}s")
                        
                        # Simulate some user interactions
                        self.simulate_map_interactions(driver)
                        
                    else:
                        session_results['errors'] += 1
                        # Take screenshot of failed load
                        failed_screenshot = self.take_screenshot(driver, user_id, load_attempt, "failed")
                        if failed_screenshot:
                            session_results['screenshots'].append(failed_screenshot)
                        
                        self.logger.warning(f"User {user_id}: Map failed to load properly")
                    
                    # Wait before next reload (simulate user thinking time)
                    time.sleep(random.randint(5, 15))
                    
                except WebDriverException as e:
                    session_results['errors'] += 1
                    # Take screenshot of error state
                    error_screenshot = self.take_screenshot(driver, user_id, load_attempt, "error")
                    if error_screenshot:
                        session_results['screenshots'].append(error_screenshot)
                    
                    self.logger.error(f"User {user_id}: WebDriver error: {e}")
                    break
                except Exception as e:
                    session_results['errors'] += 1
                    self.logger.error(f"User {user_id}: Unexpected error: {e}")
                    
        finally:
            if driver:
                driver.quit()
                
        session_results['end_time'] = time.time()
        session_results['duration'] = session_results['end_time'] - session_results['start_time']
        
        with self.lock:
            self.results.append(session_results)
            
        self.logger.info(f"User {user_id}: Session completed - {session_results['successful_loads']}/{session_results['page_loads']} successful loads")
        self.logger.info(f"User {user_id}: Screenshots saved: {len(session_results['screenshots'])}")
        return session_results

    def simulate_map_interactions(self, driver):
        """
        Simulate user interactions with the map (zooming, panning, layer toggling)
        """
        try:
            # Random zoom in/out
            if random.choice([True, False]):
                driver.execute_script("lizMap.map.zoomIn();")
                time.sleep(1)
                driver.execute_script("lizMap.map.zoomOut();")
                
            # Random pan
            if random.choice([True, False]):
                driver.execute_script("""
                    var center = lizMap.map.getCenter();
                    var newCenter = center.clone();
                    newCenter.x += (Math.random() - 0.5) * 1000;
                    newCenter.y += (Math.random() - 0.5) * 1000;
                    lizMap.map.setCenter(newCenter);
                """)
                time.sleep(1)
                
        except Exception as e:
            self.logger.debug(f"Error during map interactions: {e}")

    def run_load_test(self):
        """
        Run the complete load test with multiple concurrent users
        """
        self.logger.info(f"Starting load test with {self.concurrent_users} concurrent users for {self.test_duration} seconds")
        self.logger.info(f"Target URL: {self.base_url}")
        
        start_time = time.time()
        
        with ThreadPoolExecutor(max_workers=self.concurrent_users) as executor:
            # Submit user sessions
            futures = []
            for i in range(self.concurrent_users):
                future = executor.submit(self.simulate_user_session, i, self.test_duration)
                futures.append(future)
            
            # Wait for all sessions to complete
            for future in as_completed(futures):
                try:
                    result = future.result()
                    self.logger.info(f"Session completed: User {result['user_id']}")
                except Exception as e:
                    self.logger.error(f"Session failed: {e}")
        
        total_time = time.time() - start_time
        self.generate_report(total_time)

    def generate_report(self, total_time):
        """Generate a summary report of the load test results"""
        if not self.results:
            self.logger.error("No results to report")
            return
            
        total_loads = sum(r['page_loads'] for r in self.results)
        successful_loads = sum(r['successful_loads'] for r in self.results)
        total_errors = sum(r['errors'] for r in self.results)
        avg_load_time = sum(r['total_load_time'] for r in self.results) / successful_loads if successful_loads > 0 else 0
        
        success_rate = (successful_loads / total_loads * 100) if total_loads > 0 else 0
        
        report = f"""
========================================
LIZMAP LOAD TEST REPORT
========================================
Test Duration: {total_time:.2f} seconds
Concurrent Users: {self.concurrent_users}
Target URL: {self.base_url}

RESULTS:
Total Page Loads: {total_loads}
Successful Loads: {successful_loads}
Failed Loads: {total_errors}
Success Rate: {success_rate:.1f}%
Average Load Time: {avg_load_time:.2f} seconds

THROUGHPUT:
Requests per Second: {total_loads / total_time:.2f}
Successful Requests per Second: {successful_loads / total_time:.2f}

SCREENSHOTS:
Check the '{self.screenshot_dir}' folder for visual verification of what was loaded.
========================================
        """
        
        print(report)
        self.logger.info("Load test completed")
        
        # Save detailed results to file
        with open('lizmap_load_test_results.txt', 'w') as f:
            f.write(report)
            f.write("\nDETAILED RESULTS:\n")
            for result in self.results:
                f.write(f"User {result['user_id']}: {result['successful_loads']}/{result['page_loads']} loads, "
                       f"{result['errors']} errors, {result['duration']:.1f}s session\n")


def main():
    # Configuration
    LIZMAP_URL = "https://ifm.gisgeometer.de/index.php/view/map?repository=test&project=Test#9.350334,47.706027,9.450572,47.735585|Zeichenebenen,Skizzen_Punkte,Skizzen_Linien,Skizzen_Fl%C3%A4chen,BORIS_BW_Grundsteuer_2024,Altlasten,A_F%C3%A4lle,B_F%C3%A4lle,Altlastenfl%C3%A4chen,Wasser,W%C3%A4rmeplanung,KWP_Gebaeude,KWP_netz_gas,KWP_netz_waerme,KWP_bohrtiefenbegrenzung,KWP_neubaugebiete_geplant,KWP_wld_basisjahr_fossil,KWP_wld_zieljahr_fossil,KWP_wld_basisjahr_gesamt,KWP_wld_zieljahr_gesamt,KWP_FF_PV,KWP_FF_sth,KWP_ff_geothermie,KWP_Stadtteile,KWP_Teilgebiete,KWP_Windpotenzialflaechen_LUBW,Hochwassergefahrenkarte,Anschlaglinie_HQ100,%C3%9Cfl%C3%A4chen%20bei%20HQ10,%C3%9Cfl%C3%A4chen%20bei%20HQ100,%C3%9Cfl%C3%A4chen%20bei%20HQ50,%C3%9Cfl%C3%A4chen%20bei%20HQExtrem,Biotopverbund,Barriere_Offenland,Feuchte_Standorte,Feuchte_Standorte_Kernfl%C3%A4che,Feuchte_Standorte_Kernraum,Feuchte_Stao_Suchraum_500m,Feuchte_Stao_Suchraum_1000m,Mittlere_Standorte,Mittlere_Standorte_Kernfl%C3%A4che,Mittlere_Standorte_Kernraum,Mittlere_Stao_Suchraum_500m,Mittlere_Stao_Suchraum_1000m,Trockene_Standorte,Trockene_Standorte_Kernfl%C3%A4che,Trockene_Standorte_Kernraum,Trockene_Stao_Suchraum_500m,Trockene_Stao_Suchraur_1000m,Wildtierkorridore,Wildtierkorridor,Wildtierkorridor_Puffer_1000m,ALKIS,Gemeindegrenzen,Beschriftung,Beschriftung_M500,Grenzpunkte,OhneMarke,Abgemarkt,Bauwerke,Flurst%C3%BCcke,Geb%C3%A4ude|,default,default,default,default,,default,default,default,,,default,default,default,default,default,default,default,default,default,default,default,default,default,default,default,,default,default,default,default,default,,default,,default,default,default,default,,default,default,default,default,,default,default,default,default,,default,default,,default,,default,,default,default,default,default,default|1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1"
    
    # Test parameters - adjust these based on your needs
    CONCURRENT_USERS = 25     # Start with just 1 user for testing
    TEST_DURATION = 60       # Test duration in seconds (1 minute)
    HEADLESS = True         # Set to False to see the browsers
    
    # Create and run the load tester
    tester = LizmapLoadTester(
        base_url=LIZMAP_URL,
        concurrent_users=CONCURRENT_USERS,
        test_duration=TEST_DURATION,
        headless=HEADLESS
    )
    
    tester.run_load_test()


if __name__ == "__main__":
    main()