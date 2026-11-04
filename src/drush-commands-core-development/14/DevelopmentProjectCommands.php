<?php

namespace Drush\Commands\core_development;

use Composer\Autoload\ClassLoader;
use Drupal\Core\DrupalKernel;
use Drupal\Core\Site\Settings;
use Drush\Attributes as CLI;
use Drush\Boot\BootstrapManager;
use Drush\Boot\DrupalBootLevels;
use Drush\Commands\AutowireTrait;
use Drush\Drupal\DrushLoggerServiceProvider;
use Drush\Style\DrushStyle;
use Psr\Log\LoggerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Input\InputOption;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\HttpFoundation\Request;

/**
 * Replaces the cache:rebuild command to correctly work with symlinked Drupal.
 *
 * This prevents contrib modules from vanishing when the cache:rebuild command
 * is run.
 *
 * Drush 14 no longer supports the replace-command hook. Instead, this command
 * uses the same name, aliases, bootstrap level and static create() factory as
 * Drush\Commands\cache\CacheRebuildCommand. Site-wide commands are registered
 * after Drush's built-in commands, so this command replaces the original.
 *
 * For maintainability, changes from the original command method in
 * Drush\Commands\cache\CacheRebuildCommand are marked 'CHANGE'.
 */
#[AsCommand(
  name: self::NAME,
  description: 'Rebuild all caches',
  aliases: ['cr', 'rebuild', 'cache-rebuild'],
)]
#[CLI\Bootstrap(level: DrupalBootLevels::SITE)]
class DevelopmentProjectCommands extends Command {

  use AutowireTrait;

  const NAME = 'cache:rebuild';

  protected function __construct(
    private readonly LoggerInterface $logger,
    private readonly BootstrapManager $bootstrapManager,
    private ClassLoader $autoloader,
  ) {
    parent::__construct();
  }

  protected function configure(): void {
    $this
      ->addOption(name: 'cache-clear', mode: InputOption::VALUE_NEGATABLE, description: 'Use --no-cache-clear to suppress normal cache clearing')
      ->setHelp('This is a copy of core/rebuild.php');
  }

  public function execute(InputInterface $input, OutputInterface $output): int {
    if (str_contains(strval($input), 'cache-clear') && !$input->getoption('cache-clear')) {
      $this->logger->info("Skipping cache:rebuild due to --no-cache-clear option.");
      return self::SUCCESS;
    }

    // CHANGE: Get the app root ourselves instead of using the bootstrap
    // manager's root.
    $root = $this->getAppRoot();
    chdir($root);

    // We no longer clear APC and similar caches as they are useless on CLI.
    // See https://github.com/drush-ops/drush/pull/2450
    require_once $root . '/core/includes/utility.inc';

    $request = $this->bootstrapManager->bootstrap()->getRequest();
    DrupalKernel::bootEnvironment();

    $site_path = DrupalKernel::findSitePath($request);
    Settings::initialize($root, $site_path, $this->autoloader);

    // Coax \Drupal\Core\DrupalKernel::discoverServiceProviders to add our logger.
    $GLOBALS['conf']['container_service_providers'][] = DrushLoggerServiceProvider::class;

    // drupal_rebuild() calls drupal_flush_all_caches() itself, so we don't do it manually.
    // CHANGE: call our own version of drupal_rebuild().
    $this->drupal_rebuild($this->autoloader, $request);
    (new DrushStyle($input, $output))->success('Cache rebuild complete.');
    return Command::SUCCESS;
  }

  /**
   * Replacement for drupal_rebuild().
   *
   * This passes the app root to DrupalKernel.
   */
  function drupal_rebuild($class_loader, Request $request): void {
    // Remove Drupal's error and exception handlers; they rely on a working
    // service container and other subsystems and will only cause a fatal error
    // that hides the actual error.
    restore_error_handler();
    restore_exception_handler();

    // Invalidate the container.
    // Bootstrap up to where caches exist and clear them.
    // CHANGE: Pass the correct app root to DrupalKernel.
    $kernel = new DrupalKernel('prod', $class_loader, TRUE, $this->getAppRoot());
    $kernel->setSitePath(DrupalKernel::findSitePath($request));
    $kernel->invalidateContainer();
    $kernel->boot();
    $kernel->preHandle($request);
    // Ensure our request includes the session if appropriate.
    if (PHP_SAPI !== 'cli') {
      $request->setSession($kernel->getContainer()->get('session'));
    }

    drupal_flush_all_caches($kernel);

    // Disable recording of cached pages.
    \Drupal::service('page_cache_kill_switch')->trigger();

    // Restore Drupal's error and exception handlers.
    // @see \Drupal\Core\DrupalKernel::boot()
    set_error_handler('_drupal_error_handler');
    set_exception_handler('_drupal_exception_handler');
  }

  /**
   * Gets the app root.
   *
   * @return string
   *   The app root.
   */
  protected function getAppRoot(): string {
    // This core belongs to the project template, so we can hardcode the
    // location of this file relative to the project root, and the scaffold
    // location defined in the project's composer.json.
    return dirname(__DIR__, 3) . '/web';
  }

}
